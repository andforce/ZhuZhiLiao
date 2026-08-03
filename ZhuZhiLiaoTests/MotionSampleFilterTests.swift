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

    func testRepeatedSensorTimestampDoesNotFilterSameSampleTwice() {
        var filter = MotionSampleFilter(configuration: .init(
            deadZone: 0,
            maximumMagnitude: 10,
            smoothingFactor: 0.25
        ))

        let first = filter.process(SIMD3<Float>(1, 0, 0), timestamp: 12.5)
        let repeated = filter.process(SIMD3<Float>(1, 0, 0), timestamp: 12.5)

        XCTAssertEqual(first.x, 0.25, accuracy: 0.000_1)
        XCTAssertEqual(repeated, first)
    }

    func testElbowPivotFilterKeepsMeasuredAccelerationWhenPhoneIsStill() {
        var filter = ElbowPivotMotionFilter(configuration: .live)
        let measured = SIMD3<Float>(0.2, -0.1, 0.05)

        let output = filter.process(
            measuredAcceleration: measured,
            rotationRate: .zero,
            pivotToPhoneDirection: SIMD3<Float>(0, 1, 0),
            timestamp: 1
        )

        XCTAssertEqual(output, measured)
    }

    func testSteadyElbowRotationAddsCentripetalAccelerationTowardPivot() {
        var configuration = ElbowPivotMotionConfiguration.live
        configuration.angularSpeedDeadZone = 0
        configuration.smoothingFactor = 1
        var filter = ElbowPivotMotionFilter(configuration: configuration)

        let output = filter.process(
            measuredAcceleration: .zero,
            rotationRate: SIMD3<Float>(0, 0, 4),
            pivotToPhoneDirection: SIMD3<Float>(0, 1, 0),
            timestamp: 1
        )

        XCTAssertEqual(output.x, 0, accuracy: 0.000_1)
        XCTAssertLessThan(output.y, -0.4)
        XCTAssertEqual(output.z, 0, accuracy: 0.000_1)
    }

    func testClockwiseAndCounterclockwiseCirclesReceiveEqualAssistance() {
        var configuration = ElbowPivotMotionConfiguration.live
        configuration.angularSpeedDeadZone = 0
        configuration.smoothingFactor = 1
        var clockwiseFilter = ElbowPivotMotionFilter(configuration: configuration)
        var counterclockwiseFilter = ElbowPivotMotionFilter(configuration: configuration)

        let clockwise = clockwiseFilter.process(
            measuredAcceleration: .zero,
            rotationRate: SIMD3<Float>(0, 0, -4),
            pivotToPhoneDirection: SIMD3<Float>(0, 1, 0),
            timestamp: 1
        )
        let counterclockwise = counterclockwiseFilter.process(
            measuredAcceleration: .zero,
            rotationRate: SIMD3<Float>(0, 0, 4),
            pivotToPhoneDirection: SIMD3<Float>(0, 1, 0),
            timestamp: 1
        )

        XCTAssertEqual(clockwise.x, counterclockwise.x, accuracy: 0.000_1)
        XCTAssertEqual(clockwise.y, counterclockwise.y, accuracy: 0.000_1)
        XCTAssertEqual(clockwise.z, counterclockwise.z, accuracy: 0.000_1)
    }

    func testIncreasingElbowRotationAddsTangentialAcceleration() {
        var configuration = ElbowPivotMotionConfiguration.live
        configuration.angularSpeedDeadZone = 0
        configuration.smoothingFactor = 1
        var filter = ElbowPivotMotionFilter(configuration: configuration)

        _ = filter.process(
            measuredAcceleration: .zero,
            rotationRate: .zero,
            pivotToPhoneDirection: SIMD3<Float>(0, 1, 0),
            timestamp: 1
        )
        let output = filter.process(
            measuredAcceleration: .zero,
            rotationRate: SIMD3<Float>(0, 0, 0.1),
            pivotToPhoneDirection: SIMD3<Float>(0, 1, 0),
            timestamp: 1.01
        )

        XCTAssertLessThan(output.x, -0.2)
    }

    func testElbowPivotFilterDoesNotIntegrateRepeatedSensorSample() {
        var configuration = ElbowPivotMotionConfiguration.live
        configuration.angularSpeedDeadZone = 0
        configuration.smoothingFactor = 0.25
        var filter = ElbowPivotMotionFilter(configuration: configuration)

        let first = filter.process(
            measuredAcceleration: .zero,
            rotationRate: SIMD3<Float>(0, 0, 4),
            pivotToPhoneDirection: SIMD3<Float>(0, 1, 0),
            timestamp: 1
        )
        let repeated = filter.process(
            measuredAcceleration: .zero,
            rotationRate: SIMD3<Float>(0, 0, 4),
            pivotToPhoneDirection: SIMD3<Float>(0, 1, 0),
            timestamp: 1
        )

        XCTAssertEqual(repeated, first)
    }
}
