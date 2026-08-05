import Foundation

private struct EarthLocationRequest: Encodable {
    let enabled: Bool
    let cellID: String
}

private struct EarthLocationResponse: Decodable {
    let enabled: Bool
    let cellID: String
}

enum CounterServiceError: LocalizedError {
    case invalidResponse
    case server(Int)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回了无法识别的数据"
        case let .server(status): "服务器暂时不可用（\(status)）"
        case .notConnected: "正在连接服务器，请稍后重试"
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
        static let earthEnabled = "zzl_earth_enabled"
        static let earthCell = "zzl_earth_cell"
    }

    private let webSocketEndpoint = URL(string: "wss://zhuzhiliao.aimfor.top/api/ws")!
    private let playerEndpoint = URL(string: "https://zhuzhiliao.aimfor.top/api/players")!
    private let leaderboardEndpoint = URL(string: "https://zhuzhiliao.aimfor.top/api/leaderboard?limit=100")!
    private let deleteEndpoint = URL(string: "https://zhuzhiliao.aimfor.top/api/players/me")!
    private let earthEndpoint = URL(string: "https://zhuzhiliao.aimfor.top/api/players/me/earth")!
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
    private var earthRequests: [String: CheckedContinuation<EarthSnapshot, any Error>] = [:]

    private(set) var stats = CounterStats(online: 0, wahs: 0)
    private(set) var personalWahs: Int
    private(set) var publicCode: String?
    private(set) var earthIsEnabled: Bool
    private(set) var earthCellID: String?
    var earthRevisionHandler: ((Int) -> Void)?

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
        earthIsEnabled = defaults.bool(forKey: DefaultsKey.earthEnabled)
        earthCellID = defaults.string(forKey: DefaultsKey.earthCell)
        // Version 2 makes the anonymous score identity part of the core online
        // experience. Preserve the old opt-out key only long enough to migrate it.
        defaults.removeObject(forKey: DefaultsKey.leaderboardDisabled)
        identity = try? identityStore.load()
        publicCode = identity?.code
        if identity == nil {
            // Keychain may be cleared independently of UserDefaults. A new identity
            // must migrate from the current local total, not a removed old baseline.
            defaults.set(false, forKey: DefaultsKey.migrationCaptured)
        }
        captureMigrationIfNeeded()
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
    }

    func loadLeaderboard() async throws -> LeaderboardSnapshot {
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

    func resetAnonymousIdentity() async throws {
        let identity = try await ensureIdentity()
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
        closeSocket()
        try identityStore.delete()
        self.identity = nil
        publicCode = nil
        personalWahs = 0
        serverScore = 0
        outbox = WahOutbox()
        earthIsEnabled = false
        earthCellID = nil
        defaults.set(0, forKey: DefaultsKey.personalWahs)
        defaults.set(0, forKey: DefaultsKey.pendingWahs)
        defaults.set(false, forKey: DefaultsKey.earthEnabled)
        defaults.removeObject(forKey: DefaultsKey.earthCell)
        defaults.set(false, forKey: DefaultsKey.migrationCaptured)
        defaults.removeObject(forKey: DefaultsKey.migrationPersonal)
        captureMigrationIfNeeded()
        _ = try await ensureIdentity()
        restartConnection()
    }

    func setEarthLocation(cellID: String) async throws {
        let identity = try await ensureIdentity()
        var request = URLRequest(url: earthEndpoint)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(identity.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(EarthLocationRequest(
            enabled: true,
            cellID: cellID
        ))
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CounterServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw CounterServiceError.server(httpResponse.statusCode)
        }
        let value = try JSONDecoder().decode(EarthLocationResponse.self, from: data)
        earthIsEnabled = value.enabled
        earthCellID = value.cellID
        defaults.set(value.enabled, forKey: DefaultsKey.earthEnabled)
        defaults.set(value.cellID, forKey: DefaultsKey.earthCell)
    }

    func disableEarth() async throws {
        let identity = try await ensureIdentity()
        var request = URLRequest(url: earthEndpoint)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(identity.token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CounterServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 204 else {
            throw CounterServiceError.server(httpResponse.statusCode)
        }
        earthIsEnabled = false
        earthCellID = nil
        defaults.set(false, forKey: DefaultsKey.earthEnabled)
        defaults.removeObject(forKey: DefaultsKey.earthCell)
    }

    func loadEarthSnapshot(detail: Int, bounds: [EarthBounds] = []) async throws -> EarthSnapshot {
        guard let socket = webSocket else { throw CounterServiceError.notConnected }
        let requestID = UUID().uuidString
        let message = try CounterCodec.earthView(
            requestID: requestID,
            detail: detail,
            bounds: bounds
        )
        return try await withCheckedThrowingContinuation { continuation in
            earthRequests[requestID] = continuation
            Task { @MainActor [weak self] in
                do {
                    try await socket.send(.string(message))
                } catch {
                    self?.earthRequests.removeValue(forKey: requestID)?.resume(throwing: error)
                }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                self?.earthRequests.removeValue(forKey: requestID)?.resume(
                    throwing: URLError(.timedOut)
                )
            }
        }
    }

    private func ensureIdentity() async throws -> PlayerIdentity {
        if let identity {
            return identity
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
                let identity = try await self.ensureIdentity()
                guard self.isStarted, !Task.isCancelled else { return }
                var request = URLRequest(url: self.webSocketEndpoint)
                request.setValue(
                    "Bearer \(identity.token)",
                    forHTTPHeaderField: "Authorization"
                )
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
        case let .player(_, code, score, migrated, earthEnabled, locationCell):
            publicCode = code
            serverScore = score
            personalWahs = max(personalWahs, score)
            defaults.set(personalWahs, forKey: DefaultsKey.personalWahs)
            earthIsEnabled = earthEnabled
            earthCellID = locationCell
            defaults.set(earthEnabled, forKey: DefaultsKey.earthEnabled)
            if let locationCell {
                defaults.set(locationCell, forKey: DefaultsKey.earthCell)
            } else {
                defaults.removeObject(forKey: DefaultsKey.earthCell)
            }
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
        case let .score(score, _):
            serverScore = score
            scoreInFlight = false
        case let .earthSnapshot(snapshot):
            earthRequests.removeValue(forKey: snapshot.requestID)?.resume(returning: snapshot)
        case let .earthRevision(revision):
            earthRevisionHandler?(revision)
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
        let pendingEarthRequests = Array(earthRequests.values)
        earthRequests.removeAll()
        for continuation in pendingEarthRequests {
            continuation.resume(throwing: CounterServiceError.notConnected)
        }
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

    private func persistOutbox() {
        defaults.set(outbox.pending, forKey: DefaultsKey.pendingWahs)
    }
}
