import Foundation

struct CounterStats: Codable, Equatable, Sendable {
    let online: Int
    let wahs: Int
}

struct LeaderboardEntry: Codable, Equatable, Identifiable, Sendable {
    let code: String
    let score: Int
    let rank: Int

    var id: String { code }
}

struct LeaderboardSnapshot: Codable, Equatable, Sendable {
    let totalPlayers: Int
    let entries: [LeaderboardEntry]
    let me: LeaderboardEntry?
}

enum CounterServerMessage: Equatable, Sendable {
    case stats(CounterStats)
    case player(id: String, code: String, score: Int, migrated: Bool)
    case migration(score: Int)
    case score(Int)
    case other
}

enum CounterCodec {
    private struct WahMessage: Encodable {
        let t = "wah"
        let n: Int
    }

    private struct ScoreMessage: Encodable {
        let t = "score"
        let value: Int
    }

    private struct MigrationMessage: Encodable {
        let t = "migrate"
        let personal: Int
        let pendingGlobal: Int
    }

    private struct MessageEnvelope: Decodable {
        let t: String
        let online: Int?
        let wahs: Int?
        let id: String?
        let code: String?
        let score: Int?
        let migrated: Bool?
    }

    static func wah(count: Int) throws -> String {
        try string(WahMessage(n: min(max(count, 0), 30)))
    }

    static func score(value: Int) throws -> String {
        try string(ScoreMessage(value: max(value, 0)))
    }

    static func migration(personal: Int, pendingGlobal: Int) throws -> String {
        try string(MigrationMessage(
            personal: max(personal, 0),
            pendingGlobal: min(max(pendingGlobal, 0), max(personal, 0))
        ))
    }

    static func message(from data: Data) throws -> CounterServerMessage {
        let envelope = try JSONDecoder().decode(MessageEnvelope.self, from: data)
        switch envelope.t {
        case "stats":
            guard let online = envelope.online, let wahs = envelope.wahs else {
                throw corrupted("统计消息缺少字段")
            }
            return .stats(CounterStats(online: online, wahs: wahs))
        case "player":
            guard let id = envelope.id,
                  let code = envelope.code,
                  let score = envelope.score,
                  let migrated = envelope.migrated else {
                throw corrupted("玩家消息缺少字段")
            }
            return .player(id: id, code: code, score: score, migrated: migrated)
        case "migration":
            guard let score = envelope.score else {
                throw corrupted("迁移消息缺少分数")
            }
            return .migration(score: score)
        case "score":
            guard let score = envelope.score else {
                throw corrupted("分数确认缺少分数")
            }
            return .score(score)
        default:
            return .other
        }
    }

    static func stats(from data: Data) throws -> CounterStats {
        guard case let .stats(stats) = try message(from: data) else {
            throw corrupted("不是统计消息")
        }
        return stats
    }

    private static func string<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private static func corrupted(_ description: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: [], debugDescription: description))
    }
}
