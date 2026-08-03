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
}
