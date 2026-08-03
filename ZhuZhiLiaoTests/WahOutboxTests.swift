import XCTest
@testable import ZhuZhiLiao

final class WahOutboxTests: XCTestCase {
    func testBatchNeverExceedsWorkerLimit() {
        var outbox = WahOutbox(pending: 74)

        XCTAssertEqual(outbox.nextBatch(maximum: 30), 30)
        outbox.acknowledge(30)
        XCTAssertEqual(outbox.pending, 44)
    }

    func testFailedSendLeavesOfflineCountQueued() {
        var outbox = WahOutbox(pending: 12)
        outbox.enqueue(5)

        XCTAssertEqual(outbox.nextBatch(maximum: 30), 17)
        XCTAssertEqual(outbox.pending, 17)
    }

    func testAcknowledgementCannotRemoveMoreThanPending() {
        var outbox = WahOutbox(pending: 4)

        outbox.acknowledge(30)

        XCTAssertEqual(outbox.pending, 0)
    }
}
