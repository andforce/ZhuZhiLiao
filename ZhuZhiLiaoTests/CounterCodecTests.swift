import XCTest
@testable import ZhuZhiLiao

final class CounterCodecTests: XCTestCase {
    func testStatsMessageDecodesAllDisplayedValues() throws {
        let data = Data(#"{"t":"stats","online":12,"wahs":78}"#.utf8)

        let stats = try CounterCodec.stats(from: data)

        XCTAssertEqual(stats, CounterStats(online: 12, wahs: 78))
    }

    func testWahBatchIsCappedAtThirty() throws {
        let text: String = try CounterCodec.wah(count: 48)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )

        XCTAssertEqual(object["t"] as? String, "wah")
        XCTAssertEqual(object["n"] as? Int, 30)
    }

    func testPlayerAndScoreAcknowledgementsDecode() throws {
        let player = try CounterCodec.message(from: Data(
            #"{"t":"player","id":"player-id","code":"A7K3M9","score":42,"migrated":true}"#.utf8
        ))
        let score = try CounterCodec.message(from: Data(#"{"t":"score","score":48}"#.utf8))

        XCTAssertEqual(
            player,
            .player(id: "player-id", code: "A7K3M9", score: 42, migrated: true)
        )
        XCTAssertEqual(score, .score(48))
    }

    func testMigrationKeepsPendingWithinPersonalTotal() throws {
        let text = try CounterCodec.migration(personal: 8, pendingGlobal: 12)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )

        XCTAssertEqual(object["t"] as? String, "migrate")
        XCTAssertEqual(object["personal"] as? Int, 8)
        XCTAssertEqual(object["pendingGlobal"] as? Int, 8)
    }

    func testLeaderboardSnapshotDecodesPinnedPlayer() throws {
        let data = Data(#"""
        {
          "totalPlayers":120,
          "entries":[{"code":"FIRST1","score":99,"rank":1}],
          "me":{"code":"A7K3M9","score":12,"rank":87}
        }
        """#.utf8)

        let snapshot = try JSONDecoder().decode(LeaderboardSnapshot.self, from: data)

        XCTAssertEqual(snapshot.totalPlayers, 120)
        XCTAssertEqual(snapshot.entries.first?.rank, 1)
        XCTAssertEqual(snapshot.me, LeaderboardEntry(code: "A7K3M9", score: 12, rank: 87))
    }
}
