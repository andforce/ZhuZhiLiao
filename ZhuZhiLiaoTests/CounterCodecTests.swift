import XCTest
import simd
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
            #"{"t":"player","id":"player-id","code":"A7K3M9","score":42,"migrated":true,"earthEnabled":true,"locationCell":"v1:500:1002"}"#.utf8
        ))
        let score = try CounterCodec.message(from: Data(
            #"{"t":"score","score":48,"lastWahAt":123456}"#.utf8
        ))

        XCTAssertEqual(
            player,
            .player(
                id: "player-id",
                code: "A7K3M9",
                score: 42,
                migrated: true,
                earthEnabled: true,
                locationCell: "v1:500:1002"
            )
        )
        XCTAssertEqual(score, .score(value: 48, lastWahAt: 123456))
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

    func testEarthSnapshotDecodesPlayerAndClusterNodes() throws {
        let data = Data(#"""
        {
          "t":"earth_snapshot",
          "requestID":"request-1",
          "serverTime":1000000,
          "revision":7,
          "nodes":[
            {"kind":"player","id":"ME0001","code":"ME0001","score":19,"latitude":1.2,"longitude":2.3,"activeUntil":1120000,"isMe":true},
            {"kind":"cluster","id":"d0:3:4","latitude":5,"longitude":6,"userCount":8,"totalWahs":99,"activeCount":2,"activeUntil":1110000,"containsMe":false}
          ]
        }
        """#.utf8)

        let message = try CounterCodec.message(from: data)
        guard case let .earthSnapshot(snapshot) = message else {
            return XCTFail("Expected earth snapshot")
        }
        XCTAssertEqual(snapshot.requestID, "request-1")
        XCTAssertEqual(snapshot.nodes.count, 2)
        XCTAssertEqual(snapshot.nodes[0].displayedWahs, 19)
        XCTAssertTrue(snapshot.nodes[0].highlightsMe)
        XCTAssertEqual(snapshot.nodes[1].displayedUsers, 8)
        XCTAssertTrue(snapshot.nodes[1].isActive(serverNow: 1_000_000))
    }

    func testEarthAudioCreatesOneVoicePerPlayerAndActiveClusterMember() {
        let nodes = [
            audioEarthNode(
                id: "player",
                kind: .player,
                activeUntil: 1_120_000
            ),
            audioEarthNode(
                id: "cluster",
                kind: .cluster,
                activeCount: 3,
                activeUntil: 1_110_000
            )
        ]

        let voices = EarthAudioVoicePlanner.voices(
            nodes: nodes,
            serverNow: 1_000_000,
            serverClockOffsetMilliseconds: 0,
            localWahAt: nil
        )

        XCTAssertEqual(voices.count, 4)
        XCTAssertEqual(Set(voices.map(\.id)).count, 4)
        XCTAssertEqual(voices.filter { $0.id.hasPrefix("cluster:") }.count, 3)
    }

    func testEarthAudioOmitsExpiredNodesAndUsesServerClock() {
        let nodes = [
            audioEarthNode(id: "expired", kind: .player, activeUntil: 999_999),
            audioEarthNode(id: "active", kind: .player, activeUntil: 1_000_001)
        ]

        let voices = EarthAudioVoicePlanner.voices(
            nodes: nodes,
            serverNow: 1_000_000,
            serverClockOffsetMilliseconds: 12_000,
            localWahAt: nil
        )

        XCTAssertEqual(voices.map(\.id), ["player:active:0"])
        XCTAssertEqual(voices.first?.activeUntil, 1_000_001)
    }

    func testEarthAudioUsesLocalWahToActivateMyStaleCluster() {
        let localWahAt = Date(timeIntervalSince1970: 1_000)
        let mine = audioEarthNode(
            id: "mine",
            kind: .cluster,
            activeCount: 0,
            activeUntil: nil,
            containsMe: true
        )

        let voices = EarthAudioVoicePlanner.voices(
            nodes: [mine],
            serverNow: 1_050_500,
            serverClockOffsetMilliseconds: 500,
            localWahAt: localWahAt
        )

        XCTAssertEqual(voices.count, 1)
        XCTAssertEqual(voices.first?.activeUntil, 1_600_500)
    }

    func testEarthAudioIdentityPhaseAndGainAreStable() throws {
        let node = audioEarthNode(
            id: "stable",
            kind: .cluster,
            activeCount: 2,
            activeUntil: 1_120_000
        )
        let first = EarthAudioVoicePlanner.voices(
            nodes: [node],
            serverNow: 1_000_000,
            serverClockOffsetMilliseconds: 0,
            localWahAt: nil
        )
        let second = EarthAudioVoicePlanner.voices(
            nodes: [node],
            serverNow: 1_000_100,
            serverClockOffsetMilliseconds: 0,
            localWahAt: nil
        )

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first[0].normalizedStartPhase, first[1].normalizedStartPhase)
        XCTAssertEqual(EarthAudioVoicePlanner.normalizedGain(voiceCount: 0), 0)
        XCTAssertEqual(
            EarthAudioVoicePlanner.normalizedGain(voiceCount: 4, isMuted: true),
            0
        )
        XCTAssertEqual(
            EarthAudioVoicePlanner.normalizedGain(voiceCount: 4),
            0.4,
            accuracy: 0.000_1
        )
    }

    func testEarthViewClampsDetailAndEncodesBounds() throws {
        let text = try CounterCodec.earthView(
            requestID: "view",
            detail: 9,
            bounds: [EarthBounds(
                minLatitude: -10,
                maxLatitude: 10,
                minLongitude: 170,
                maxLongitude: 180
            )]
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["t"] as? String, "earth_view")
        XCTAssertEqual(object["detail"] as? Int, 4)
        XCTAssertEqual((object["bounds"] as? [[String: Any]])?.count, 1)
    }

    func testEarthLocationGridIsStableAndNeverContainsRawCoordinates() throws {
        let first = try XCTUnwrap(EarthLocationGrid.cellID(latitude: 31.2304, longitude: 121.4737))
        let nearby = try XCTUnwrap(EarthLocationGrid.cellID(latitude: 31.2310, longitude: 121.4740))

        XCTAssertEqual(first, nearby)
        XCTAssertTrue(first.hasPrefix("v1:"))
        XCTAssertFalse(first.contains("31.2304"))
        XCTAssertNil(EarthLocationGrid.cellID(latitude: 91, longitude: 0))
    }

    func testEarthFocusPrioritizesMyCoordinate() {
        let nearby = earthNode(id: "nearby", latitude: 0, longitude: -15)
        let mine = earthNode(
            id: "mine",
            latitude: 31,
            longitude: 121,
            kind: .cluster,
            containsMe: true
        )

        let preferred = EarthCameraFocus.preferredNode(
            in: [nearby, mine],
            from: EarthCameraFocus.initialAngles
        )

        XCTAssertEqual(preferred?.id, "mine")
    }

    func testEarthFocusFallsBackToCoordinateNearestScreenCenter() {
        let centered = earthNode(id: "centered", latitude: 2, longitude: 168)
        let farAway = earthNode(id: "far-away", latitude: 30, longitude: 120)

        let preferred = EarthCameraFocus.preferredNode(
            in: [farAway, centered],
            from: EarthCameraFocus.initialAngles
        )

        XCTAssertEqual(preferred?.id, "centered")
    }

    func testEarthFocusCenteredAnglesPutCoordinateAtFrontCenter() {
        for coordinate in [(31.23, 121.47), (-33.87, 151.21), (64.15, -21.94)] {
            let target = earthNode(
                id: "target",
                latitude: coordinate.0,
                longitude: coordinate.1
            )
            let angles = EarthCameraFocus.centeredAngles(for: target)
            let point = EarthBoundaryLoader.spherePoint(
                latitude: target.latitude,
                longitude: target.longitude
            )
            let globe = simd_float4x4.rotation(
                angle: angles.yaw,
                axis: SIMD3<Float>(0, 1, 0)
            ) * simd_float4x4.rotation(
                angle: angles.pitch,
                axis: SIMD3<Float>(1, 0, 0)
            )
            let centeredPoint = globe * SIMD4<Float>(point, 1)

            XCTAssertEqual(centeredPoint.x, 0, accuracy: 0.000_1)
            XCTAssertEqual(centeredPoint.y, 0, accuracy: 0.000_1)
            XCTAssertGreaterThan(centeredPoint.z, 0.999)
        }
    }

    private func earthNode(
        id: String,
        latitude: Double,
        longitude: Double,
        kind: EarthNode.Kind = .player,
        isMe: Bool = false,
        containsMe: Bool = false
    ) -> EarthNode {
        EarthNode(
            kind: kind,
            id: id,
            code: id,
            score: 1,
            latitude: latitude,
            longitude: longitude,
            userCount: nil,
            totalWahs: nil,
            activeCount: nil,
            activeUntil: nil,
            isMe: isMe,
            containsMe: containsMe
        )
    }

    private func audioEarthNode(
        id: String,
        kind: EarthNode.Kind,
        activeCount: Int? = nil,
        activeUntil: Int64?,
        isMe: Bool = false,
        containsMe: Bool = false
    ) -> EarthNode {
        EarthNode(
            kind: kind,
            id: id,
            code: kind == .player ? id : nil,
            score: kind == .player ? 1 : nil,
            latitude: 0,
            longitude: 0,
            userCount: kind == .cluster ? max(activeCount ?? 0, 1) : nil,
            totalWahs: kind == .cluster ? 1 : nil,
            activeCount: activeCount,
            activeUntil: activeUntil,
            isMe: isMe,
            containsMe: containsMe
        )
    }
}
