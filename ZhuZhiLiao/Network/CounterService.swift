import Foundation

enum CounterServiceError: LocalizedError {
    case invalidResponse
    case server(Int)
    case leaderboardDisabled

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回了无法识别的数据"
        case let .server(status): "服务器暂时不可用（\(status)）"
        case .leaderboardDisabled: "你已退出排行榜"
        }
    }
}

@MainActor
final class CounterService {
    private enum DefaultsKey {
        static let personalWahs = "zzl_mywah"
        static let pendingWahs = "zzl_pending_wah"
        static let migrationCaptured = "zzl_rank_migration_captured"
        static let migrationPersonal = "zzl_rank_migration_personal"
        static let leaderboardDisabled = "zzl_rank_disabled"
    }

    private let webSocketEndpoint = URL(string: "wss://zhuzhiliao.aimfor.top/api/ws")!
    private let playerEndpoint = URL(string: "https://zhuzhiliao.aimfor.top/api/players")!
    private let leaderboardEndpoint = URL(string: "https://zhuzhiliao.aimfor.top/api/leaderboard?limit=100")!
    private let deleteEndpoint = URL(string: "https://zhuzhiliao.aimfor.top/api/players/me")!
    private let defaults: UserDefaults
    private let session: URLSession
    private let identityStore: PlayerIdentityStore

    private var identity: PlayerIdentity?
    private var webSocket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var isStarted = false
    private var isMigrated = false
    private var migrationInFlight = false
    private var scoreInFlight = false
    private var serverScore = 0
    private var outbox: WahOutbox

    private(set) var stats = CounterStats(online: 0, wahs: 0)
    private(set) var personalWahs: Int
    private(set) var isLeaderboardParticipant: Bool
    private(set) var publicCode: String?

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        identityStore: PlayerIdentityStore = PlayerIdentityStore()
    ) {
        self.defaults = defaults
        self.session = session
        self.identityStore = identityStore
        personalWahs = defaults.integer(forKey: DefaultsKey.personalWahs)
        outbox = WahOutbox(pending: defaults.integer(forKey: DefaultsKey.pendingWahs))
        isLeaderboardParticipant = !defaults.bool(forKey: DefaultsKey.leaderboardDisabled)
        identity = try? identityStore.load()
        publicCode = identity?.code
        if isLeaderboardParticipant {
            if identity == nil {
                // Keychain may be cleared independently of UserDefaults. A new identity
                // must migrate from the current local total, not a removed old baseline.
                defaults.set(false, forKey: DefaultsKey.migrationCaptured)
            }
            captureMigrationIfNeeded()
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        connect()

        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.2))
                guard let self else { return }
                await self.flushPendingWahs()
            }
        }

        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard let self else { return }
                await self.sendPing()
            }
        }
    }

    func stop() {
        isStarted = false
        connectionTask?.cancel()
        flushTask?.cancel()
        heartbeatTask?.cancel()
        connectionTask = nil
        flushTask = nil
        heartbeatTask = nil
        closeSocket()
        persistOutbox()
    }

    func record(wahs count: Int) {
        guard count > 0 else { return }
        personalWahs += count
        defaults.set(personalWahs, forKey: DefaultsKey.personalWahs)
        if !isLeaderboardParticipant {
            outbox.enqueue(count)
            persistOutbox()
        }
    }

    func loadLeaderboard() async throws -> LeaderboardSnapshot {
        guard isLeaderboardParticipant else {
            throw CounterServiceError.leaderboardDisabled
        }
        let identity = try await ensureIdentity()
        var request = URLRequest(url: leaderboardEndpoint)
        request.setValue("Bearer \(identity.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CounterServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw CounterServiceError.server(httpResponse.statusCode)
        }
        return try JSONDecoder().decode(LeaderboardSnapshot.self, from: data)
    }

    func joinLeaderboard() async throws {
        guard !isLeaderboardParticipant else { return }
        defaults.set(false, forKey: DefaultsKey.leaderboardDisabled)
        isLeaderboardParticipant = true
        defaults.set(false, forKey: DefaultsKey.migrationCaptured)
        captureMigrationIfNeeded()
        _ = try await ensureIdentity()
        restartConnection()
    }

    func deleteLeaderboardIdentity() async throws {
        guard let identity else {
            disableLeaderboard()
            return
        }
        var request = URLRequest(url: deleteEndpoint)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(identity.token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CounterServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 401 else {
            throw CounterServiceError.server(httpResponse.statusCode)
        }
        try identityStore.delete()
        disableLeaderboard()
        restartConnection()
    }

    private func ensureIdentity() async throws -> PlayerIdentity {
        if let identity {
            return identity
        }
        guard isLeaderboardParticipant else {
            throw CounterServiceError.leaderboardDisabled
        }
        var request = URLRequest(url: playerEndpoint)
        request.httpMethod = "POST"
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CounterServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 201 else {
            throw CounterServiceError.server(httpResponse.statusCode)
        }
        let created = try JSONDecoder().decode(PlayerIdentity.self, from: data)
        try identityStore.save(created)
        identity = created
        publicCode = created.code
        return created
    }

    private func connect() {
        guard isStarted, webSocket == nil, connectionTask == nil else { return }
        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let identity = self.isLeaderboardParticipant
                    ? try await self.ensureIdentity()
                    : nil
                guard self.isStarted, !Task.isCancelled else { return }
                var request = URLRequest(url: self.webSocketEndpoint)
                if let identity {
                    request.setValue(
                        "Bearer \(identity.token)",
                        forHTTPHeaderField: "Authorization"
                    )
                }
                let socket = self.session.webSocketTask(with: request)
                self.webSocket = socket
                self.connectionTask = nil
                self.reconnectAttempt = 0
                socket.resume()
                await self.receiveMessages(from: socket)
            } catch {
                self.connectionTask = nil
                self.scheduleReconnect()
            }
        }
    }

    private func receiveMessages(from socket: URLSessionWebSocketTask) async {
        do {
            while isStarted, socket === webSocket {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case let .data(value): data = value
                case let .string(value): data = Data(value.utf8)
                @unknown default: continue
                }
                guard let decoded = try? CounterCodec.message(from: data) else { continue }
                await handle(decoded, socket: socket)
            }
        } catch {
            handleDisconnect(socket)
        }
    }

    private func handle(_ message: CounterServerMessage, socket: URLSessionWebSocketTask) async {
        switch message {
        case let .stats(value):
            stats = value
        case let .player(_, code, score, migrated):
            publicCode = code
            serverScore = score
            personalWahs = max(personalWahs, score)
            defaults.set(personalWahs, forKey: DefaultsKey.personalWahs)
            isMigrated = migrated
            if migrated {
                finishMigration()
            } else {
                await sendMigration(on: socket)
            }
        case let .migration(score):
            migrationInFlight = false
            serverScore = score
            personalWahs = max(personalWahs, score)
            defaults.set(personalWahs, forKey: DefaultsKey.personalWahs)
            isMigrated = true
            finishMigration()
        case let .score(score):
            serverScore = score
            scoreInFlight = false
        case .other:
            break
        }
    }

    private func sendMigration(on socket: URLSessionWebSocketTask) async {
        guard !migrationInFlight else { return }
        migrationInFlight = true
        do {
            let personal = defaults.integer(forKey: DefaultsKey.migrationPersonal)
            let message = try CounterCodec.migration(
                personal: personal,
                pendingGlobal: outbox.pending
            )
            try await socket.send(.string(message))
        } catch {
            migrationInFlight = false
            handleDisconnect(socket)
        }
    }

    private func flushPendingWahs() async {
        guard let socket = webSocket else { return }
        if !isLeaderboardParticipant {
            guard outbox.pending > 0 else { return }
            let count = outbox.nextBatch(maximum: 30)
            do {
                try await socket.send(.string(try CounterCodec.wah(count: count)))
                outbox.acknowledge(count)
                persistOutbox()
            } catch {
                handleDisconnect(socket)
            }
            return
        }

        guard isMigrated, !scoreInFlight, serverScore < personalWahs else { return }
        scoreInFlight = true
        let target = min(personalWahs, serverScore + 30)
        do {
            try await socket.send(.string(try CounterCodec.score(value: target)))
        } catch {
            scoreInFlight = false
            handleDisconnect(socket)
        }
    }

    private func sendPing() async {
        guard let socket = webSocket else { return }
        do {
            try await socket.send(.string("ping"))
        } catch {
            handleDisconnect(socket)
        }
    }

    private func handleDisconnect(_ socket: URLSessionWebSocketTask) {
        guard socket === webSocket else { return }
        closeSocket()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard isStarted, connectionTask == nil else { return }
        let delay = min(30.0, pow(2.0, Double(reconnectAttempt)))
        reconnectAttempt += 1
        connectionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.connectionTask = nil
            self.connect()
        }
    }

    private func restartConnection() {
        closeSocket()
        connectionTask?.cancel()
        connectionTask = nil
        reconnectAttempt = 0
        connect()
    }

    private func closeSocket() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        migrationInFlight = false
        scoreInFlight = false
        isMigrated = false
    }

    private func captureMigrationIfNeeded() {
        guard !defaults.bool(forKey: DefaultsKey.migrationCaptured) else { return }
        defaults.set(personalWahs, forKey: DefaultsKey.migrationPersonal)
        defaults.set(true, forKey: DefaultsKey.migrationCaptured)
    }

    private func finishMigration() {
        outbox.acknowledge(outbox.pending)
        persistOutbox()
        defaults.removeObject(forKey: DefaultsKey.migrationPersonal)
    }

    private func disableLeaderboard() {
        defaults.set(true, forKey: DefaultsKey.leaderboardDisabled)
        defaults.set(false, forKey: DefaultsKey.migrationCaptured)
        defaults.removeObject(forKey: DefaultsKey.migrationPersonal)
        isLeaderboardParticipant = false
        identity = nil
        publicCode = nil
        isMigrated = false
        serverScore = 0
    }

    private func persistOutbox() {
        defaults.set(outbox.pending, forKey: DefaultsKey.pendingWahs)
    }
}
