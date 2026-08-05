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

    func testRepeatedShakesAlongEveryAxisActivateDrive() {
        for axis in [
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0, 0, 1)
        ] {
            var detector = ShakeGestureDetector()
            let result = driveSineShake(
                detector: &detector,
                axis: axis,
                amplitude: 0.45,
                frequency: 3,
                duration: 0.8
            )

            XCTAssertTrue(result.drive.isActive, "axis: \(axis)")
            XCTAssertGreaterThan(result.maximumIntensity, 0.05, "axis: \(axis)")
            XCTAssertEqual(result.drive.orbitAxis.z, -1, accuracy: 0.000_1)
        }
    }

    func testCircularShakeActivatesAndInfersRotationAxis() {
        var detector = ShakeGestureDetector()
        var drive = ShakeDrive.inactive
        let step = 0.01

        for index in 0...80 {
            let time = Double(index) * step
            let phase = Float(time * 3 * 2 * .pi)
            drive = detector.process(
                acceleration: SIMD3<Float>(cos(phase), sin(phase), 0) * 0.45,
                rotationRate: .zero,
                timestamp: time
            )
        }

        XCTAssertTrue(drive.isActive)
        XCTAssertGreaterThan(drive.orbitAxis.z, 0.9)
        XCTAssertGreaterThan(drive.directionConfidence, 0)
    }

    func testStrongerShakeProducesMoreDriveIntensity() {
        var gentleDetector = ShakeGestureDetector()
        var strongDetector = ShakeGestureDetector()

        let gentle = driveSineShake(
            detector: &gentleDetector,
            axis: SIMD3<Float>(1, 0, 0),
            amplitude: 0.30,
            frequency: 2.5,
            duration: 0.8
        )
        let strong = driveSineShake(
            detector: &strongDetector,
            axis: SIMD3<Float>(1, 0, 0),
            amplitude: 0.85,
            frequency: 3.5,
            duration: 0.8
        )

        XCTAssertGreaterThan(strong.maximumIntensity, gentle.maximumIntensity)
    }

    func testStationaryNoiseSingleImpulseAndWalkingDoNotActivate() {
        var noiseDetector = ShakeGestureDetector()
        var impulseDetector = ShakeGestureDetector()
        var walkingDetector = ShakeGestureDetector()
        var noiseDrive = ShakeDrive.inactive
        var impulseDrive = ShakeDrive.inactive
        var walkingDrive = ShakeDrive.inactive

        for index in 0...100 {
            let time = Double(index) * 0.01
            let phase = Float(time * 2 * .pi)
            noiseDrive = noiseDetector.process(
                acceleration: SIMD3<Float>(sin(phase), cos(phase), 0) * 0.015,
                rotationRate: .zero,
                timestamp: time
            )
            walkingDrive = walkingDetector.process(
                acceleration: SIMD3<Float>(0, sin(phase * 1.7), 0) * 0.16,
                rotationRate: .zero,
                timestamp: time
            )

            let impulse: SIMD3<Float>
            switch index {
            case 20..<25:
                impulse = SIMD3<Float>(0.8, 0, 0)
            case 25..<30:
                impulse = SIMD3<Float>(-0.8, 0, 0)
            default:
                impulse = .zero
            }
            impulseDrive = impulseDetector.process(
                acceleration: impulse,
                rotationRate: .zero,
                timestamp: time
            )
        }

        XCTAssertFalse(noiseDrive.isActive)
        XCTAssertFalse(walkingDrive.isActive)
        XCTAssertFalse(impulseDrive.isActive)
    }

    func testDriveStopsAndIntensityDecaysAfterInputBecomesIdle() {
        var detector = ShakeGestureDetector()
        let active = driveSineShake(
            detector: &detector,
            axis: SIMD3<Float>(1, 0, 0),
            amplitude: 0.55,
            frequency: 3,
            duration: 0.8
        ).drive
        var drive = active

        for index in 1...70 {
            drive = detector.process(
                acceleration: .zero,
                rotationRate: .zero,
                timestamp: 0.8 + Double(index) * 0.01
            )
        }

        XCTAssertTrue(active.isActive)
        XCTAssertFalse(drive.isActive)
        XCTAssertLessThan(drive.intensity, active.intensity)
    }

    func testActiveDirectionIgnoresBriefOppositeEvidenceButAcceptsSustainedReversal() {
        var detector = ShakeGestureDetector()
        var drive = circularShake(
            detector: &detector,
            direction: 1,
            startTime: 0,
            duration: 0.8
        )
        XCTAssertGreaterThan(drive.orbitAxis.z, 0.9)

        drive = detector.process(
            acceleration: SIMD3<Float>(0.45, 0, 0),
            rotationRate: SIMD3<Float>(0, 0, -2),
            timestamp: 0.81
        )
        XCTAssertGreaterThan(drive.orbitAxis.z, 0.9)

        for index in 1...36 {
            let direction: Float = index.isMultiple(of: 6) ? -1 : 1
            drive = detector.process(
                acceleration: SIMD3<Float>(direction * 0.45, 0, 0),
                rotationRate: SIMD3<Float>(0, 0, -2),
                timestamp: 0.81 + Double(index) * 0.01
            )
        }

        XCTAssertLessThan(drive.orbitAxis.z, -0.9)
    }

    func testResetCanPreserveLastInferredDirection() {
        var detector = ShakeGestureDetector()
        let drive = circularShake(
            detector: &detector,
            direction: 1,
            startTime: 0,
            duration: 0.8
        )

        let resetDrive = detector.reset(preservingOrbitAxis: true)

        XCTAssertFalse(resetDrive.isActive)
        XCTAssertEqual(resetDrive.orbitAxis.x, drive.orbitAxis.x, accuracy: 0.000_1)
        XCTAssertEqual(resetDrive.orbitAxis.y, drive.orbitAxis.y, accuracy: 0.000_1)
        XCTAssertEqual(resetDrive.orbitAxis.z, drive.orbitAxis.z, accuracy: 0.000_1)
    }

    func testShakeDetectorDoesNotProcessRepeatedTimestampTwice() {
        var detector = ShakeGestureDetector()
        _ = detector.process(
            acceleration: .zero,
            rotationRate: .zero,
            timestamp: 1
        )
        let first = detector.process(
            acceleration: SIMD3<Float>(0.8, 0, 0),
            rotationRate: .zero,
            timestamp: 1.01
        )
        let repeated = detector.process(
            acceleration: SIMD3<Float>(-0.8, 0, 0),
            rotationRate: SIMD3<Float>(0, 0, 3),
            timestamp: 1.01
        )

        XCTAssertEqual(repeated, first)
    }

    private func driveSineShake(
        detector: inout ShakeGestureDetector,
        axis: SIMD3<Float>,
        amplitude: Float,
        frequency: Float,
        duration: TimeInterval,
        startTime: TimeInterval = 0
    ) -> (drive: ShakeDrive, maximumIntensity: Float) {
        var drive = ShakeDrive.inactive
        var maximumIntensity: Float = 0
        let sampleCount = Int(duration * 100)

        for index in 0...sampleCount {
            let time = startTime + Double(index) * 0.01
            let phase = Float((time - startTime) * Double(frequency) * 2 * .pi)
            drive = detector.process(
                acceleration: axis * (sin(phase) * amplitude),
                rotationRate: .zero,
                timestamp: time
            )
            maximumIntensity = max(maximumIntensity, drive.intensity)
        }
        return (drive, maximumIntensity)
    }

    private func circularShake(
        detector: inout ShakeGestureDetector,
        direction: Float,
        startTime: TimeInterval,
        duration: TimeInterval
    ) -> ShakeDrive {
        var drive = ShakeDrive.inactive
        let sampleCount = Int(duration * 100)
        for index in 0...sampleCount {
            let time = startTime + Double(index) * 0.01
            let phase = direction
                * Float((time - startTime) * 3 * 2 * .pi)
            drive = detector.process(
                acceleration: SIMD3<Float>(cos(phase), sin(phase), 0) * 0.45,
                rotationRate: .zero,
                timestamp: time
            )
        }
        return drive
    }
}
