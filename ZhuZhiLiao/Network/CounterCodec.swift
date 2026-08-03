import Foundation

struct CounterStats: Codable, Equatable, Sendable {
    let online: Int
    let visitors: Int
    let visits: Int
    let wahs: Int
}

enum CounterCodec {
    private struct HelloMessage: Encodable {
        let t = "hi"
        let uid: String
        let v: Int
    }

    private struct WahMessage: Encodable {
        let t = "wah"
        let n: Int
    }

    private struct StatsMessage: Decodable {
        let t: String
        let online: Int
        let visitors: Int
        let visits: Int
        let wahs: Int
    }

    static func hello(userID: String, countsVisit: Bool) throws -> String {
        let data = try JSONEncoder().encode(
            HelloMessage(uid: userID, v: countsVisit ? 1 : 0)
        )
        return String(decoding: data, as: UTF8.self)
    }

    static func wah(count: Int) throws -> String {
        let data = try JSONEncoder().encode(WahMessage(n: min(max(count, 0), 30)))
        return String(decoding: data, as: UTF8.self)
    }

    static func stats(from data: Data) throws -> CounterStats {
        let message = try JSONDecoder().decode(StatsMessage.self, from: data)
        guard message.t == "stats" else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "不是统计消息")
            )
        }
        return CounterStats(
            online: message.online,
            visitors: message.visitors,
            visits: message.visits,
            wahs: message.wahs
        )
    }
}
