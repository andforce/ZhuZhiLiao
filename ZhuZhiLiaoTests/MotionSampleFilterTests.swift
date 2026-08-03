import XCTest
import simd
@testable import ZhuZhiLiao

final class MotionSampleFilterTests: XCTestCase {
    func testAccelerationInsideDeadZoneBecomesZero() {
        var filter = MotionSampleFilter(
            configuration: .init(deadZone: 0.03, maximumMagnitude: 2.5, smoothingFactor: 1)
        )

        XCTAssertEqual(filter.process(SIMD3<Float>(0.02, 0, 0)), .zero)
    }

    func testAccelerationIsClampedBeforeItReachesSimulation() {
        var filter = MotionSampleFilter(
            configuration: .init(deadZone: 0, maximumMagnitude: 2.5, smoothingFactor: 1)
        )

        let output = filter.process(SIMD3<Float>(5, 0, 0))

        XCTAssertEqual(output.x, 2.5, accuracy: 0.0001)
        XCTAssertEqual(output.y, 0, accuracy: 0.0001)
        XCTAssertEqual(output.z, 0, accuracy: 0.0001)
    }

    func testSmoothingBlendsTowardLatestSample() {
        var filter = MotionSampleFilter(
            configuration: .init(deadZone: 0, maximumMagnitude: 2.5, smoothingFactor: 0.25)
        )

        _ = filter.process(.zero)
        let output = filter.process(SIMD3<Float>(1, 0, 0))

        XCTAssertEqual(output.x, 0.25, accuracy: 0.0001)
    }
}

