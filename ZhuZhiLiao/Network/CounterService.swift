import Foundation

@MainActor
final class CounterService {
    private enum DefaultsKey {
        static let legacyUserID = "zzl_uid"
        static let personalWahs = "zzl_mywah"
        static let pendingWahs = "zzl_pending_wah"
    }

    private let endpoint = URL(string: "wss://zhuzhiliao.aimfor.top/api/ws")!
    private let defaults: UserDefaults
    private let session: URLSession

    private var webSocket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var isStarted = false
    private var outbox: WahOutbox

    private(set) var stats = CounterStats(online: 0, wahs: 0)
    private(set) var personalWahs: Int

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session

        defaults.removeObject(forKey: DefaultsKey.legacyUserID)
        personalWahs = defaults.integer(forKey: DefaultsKey.personalWahs)
        outbox = WahOutbox(pending: defaults.integer(forKey: DefaultsKey.pendingWahs))
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
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        defaults.set(outbox.pending, forKey: DefaultsKey.pendingWahs)
    }

    func record(wahs count: Int) {
        guard count > 0 else { return }
        personalWahs += count
        outbox.enqueue(count)
        defaults.set(personalWahs, forKey: DefaultsKey.personalWahs)
        defaults.set(outbox.pending, forKey: DefaultsKey.pendingWahs)
    }

    private func connect() {
        guard isStarted, webSocket == nil else { return }

        let socket = session.webSocketTask(with: endpoint)
        webSocket = socket
        socket.resume()

        connectionTask = Task { [weak self, socket] in
            guard let self else { return }
            self.reconnectAttempt = 0
            await self.receiveMessages(from: socket)
        }
    }

    private func receiveMessages(from socket: URLSessionWebSocketTask) async {
        do {
            while isStarted, socket === webSocket {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case let .data(value):
                    data = value
                case let .string(value):
                    data = Data(value.utf8)
                @unknown default:
                    continue
                }
                if let decoded = try? CounterCodec.stats(from: data) {
                    stats = decoded
                }
            }
        } catch {
            handleDisconnect(socket)
        }
    }

    private func handleDisconnect(_ socket: URLSessionWebSocketTask) {
        guard socket === webSocket else { return }
        webSocket = nil
        guard isStarted else { return }

        let delay = min(30.0, pow(2.0, Double(reconnectAttempt)))
        reconnectAttempt += 1
        connectionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.connect()
        }
    }

    private func flushPendingWahs() async {
        guard outbox.pending > 0, let socket = webSocket else { return }
        let count = outbox.nextBatch(maximum: 30)

        do {
            let message = try CounterCodec.wah(count: count)
            try await socket.send(.string(message))
            outbox.acknowledge(count)
            defaults.set(outbox.pending, forKey: DefaultsKey.pendingWahs)
        } catch {
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
}
