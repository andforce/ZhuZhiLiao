import XCTest
import simd
@testable import ZhuZhiLiao

final class ToySimulationTests: XCTestCase {
    func testFixedStepProducesSameResultAtSixtyAndOneHundredTwentyFramesPerSecond() {
        let configuration = ToyPhysicsConfiguration.testing
        var sixtyFPS = ToySimulation(configuration: configuration)
        var oneTwentyFPS = ToySimulation(configuration: configuration)
        let input = MotionInput(
            anchorAcceleration: SIMD3<Float>(0.7, -0.2, 0.35),
            gravityDirection: SIMD3<Float>(0, -1, 0),
            rotationRate: .zero
        )

        for _ in 0..<60 {
            _ = sixtyFPS.advance(input: input, deltaTime: 1.0 / 60.0)
        }
        for _ in 0..<120 {
            _ = oneTwentyFPS.advance(input: input, deltaTime: 1.0 / 120.0)
        }

        XCTAssertEqual(sixtyFPS.state.position.x, oneTwentyFPS.state.position.x, accuracy: 0.002)
        XCTAssertEqual(sixtyFPS.state.position.y, oneTwentyFPS.state.position.y, accuracy: 0.002)
        XCTAssertEqual(sixtyFPS.state.position.z, oneTwentyFPS.state.position.z, accuracy: 0.002)
        XCTAssertEqual(sixtyFPS.state.velocity.x, oneTwentyFPS.state.velocity.x, accuracy: 0.002)
        XCTAssertEqual(sixtyFPS.state.velocity.y, oneTwentyFPS.state.velocity.y, accuracy: 0.002)
        XCTAssertEqual(sixtyFPS.state.velocity.z, oneTwentyFPS.state.velocity.z, accuracy: 0.002)
    }

    func testPointerAnchorMotionPreservesBobWorldInertia() {
        let initial = ToyPhysicsState(
            position: SIMD3<Float>(1, 0, 0),
            velocity: .zero,
            ropeLength: 2,
            angularVelocity: .zero,
            tension: 0,
            activity: 0
        )
        var simulation = ToySimulation(
            state: initial,
            configuration: .inertialTesting
        )
        let initialWorldPosition = initial.anchorOffset + initial.position
        let input = MotionInput(
            anchorAcceleration: .zero,
            gravityDirection: .zero,
            rotationRate: .zero,
            anchorTarget: SIMD3<Float>(0.8, 0.2, 0)
        )

        _ = simulation.advance(input: input, deltaTime: 1.0 / 60.0)

        let worldPosition = simulation.state.anchorOffset + simulation.state.position
        XCTAssertEqual(worldPosition.x, initialWorldPosition.x, accuracy: 0.000_1)
        XCTAssertEqual(worldPosition.y, initialWorldPosition.y, accuracy: 0.000_1)
        XCTAssertGreaterThan(simulation.state.anchorOffset.x, 0)
        XCTAssertLessThan(simulation.state.position.x, initial.position.x)
    }

    func testPointerInputIsFrameRateIndependent() {
        var sixtyFPS = ToySimulation(configuration: .inertialTesting)
        var oneTwentyFPS = ToySimulation(configuration: .inertialTesting)
        let input = MotionInput(
            anchorAcceleration: .zero,
            gravityDirection: .zero,
            rotationRate: .zero,
            anchorTarget: SIMD3<Float>(0.7, -0.25, 0.1)
        )

        for _ in 0..<60 {
            _ = sixtyFPS.advance(input: input, deltaTime: 1.0 / 60.0)
        }
        for _ in 0..<120 {
            _ = oneTwentyFPS.advance(input: input, deltaTime: 1.0 / 120.0)
        }

        XCTAssertEqual(sixtyFPS.state.anchorOffset.x, oneTwentyFPS.state.anchorOffset.x, accuracy: 0.000_1)
        XCTAssertEqual(sixtyFPS.state.anchorOffset.y, oneTwentyFPS.state.anchorOffset.y, accuracy: 0.000_1)
        XCTAssertEqual(sixtyFPS.state.position.x, oneTwentyFPS.state.position.x, accuracy: 0.002)
        XCTAssertEqual(sixtyFPS.state.position.y, oneTwentyFPS.state.position.y, accuracy: 0.002)
    }

    func testWebRopeShapeMatchesReferenceSagAndEndpoints() {
        let anchor = SIMD3<Float>(0, 0, 0)
        let bob = SIMD3<Float>(0, -1, 0)
        let points = WebRopeShape.points(
            anchor: anchor,
            bob: bob,
            ropeLength: 2,
            count: 5
        )

        XCTAssertEqual(points.first, anchor)
        XCTAssertEqual(points.last, bob)
        // 网页公式：slack * .55 * sin(pi*t) * (1 - .25*t)，t = .5。
        XCTAssertEqual(points[2].y, -0.981_25, accuracy: 0.000_1)
        let nearAnchorSag = -0.25 - points[1].y
        let nearBobSag = -0.75 - points[3].y
        XCTAssertGreaterThan(nearBobSag, nearAnchorSag)
    }

    func testCrossProductDeterminesPositiveRotationDirection() {
        let initial = ToyPhysicsState(
            position: SIMD3<Float>(1, 0, 0),
            velocity: SIMD3<Float>(0, 2, 0),
            ropeLength: 2,
            angularVelocity: .zero,
            tension: 0,
            activity: 0
        )
        var simulation = ToySimulation(
            state: initial,
            configuration: .inertialTesting
        )

        _ = simulation.advance(input: .zero, deltaTime: 1.0 / 240.0)

        XCTAssertGreaterThan(simulation.state.angularVelocity.z, 0)
    }

    func testOppositeOrbitDirectionsProduceOppositeVisualPhase() {
        let positiveState = ToyPhysicsState(
            position: SIMD3<Float>(1, 0, 0),
            velocity: SIMD3<Float>(0, 1, 0),
            ropeLength: 1,
            angularVelocity: .zero,
            tension: 1,
            activity: 1
        )
        let negativeState = ToyPhysicsState(
            position: SIMD3<Float>(1, 0, 0),
            velocity: SIMD3<Float>(0, -1, 0),
            ropeLength: 1,
            angularVelocity: .zero,
            tension: 1,
            activity: 1
        )
        var positive = ToySimulation(state: positiveState, configuration: .inertialTesting)
        var negative = ToySimulation(state: negativeState, configuration: .inertialTesting)

        let positiveFrame = positive.advance(input: .zero, deltaTime: 1.0 / 240.0)
        let negativeFrame = negative.advance(input: .zero, deltaTime: 1.0 / 240.0)

        XCTAssertGreaterThan(positiveFrame.phase, 0)
        XCTAssertLessThan(negativeFrame.phase, 0)
    }

    func testForwardPhoneAccelerationMovesTubeIntoDepthInOppositeDirection() {
        var simulation = ToySimulation(configuration: .inertialTesting)
        let input = MotionInput(
            anchorAcceleration: SIMD3<Float>(0, 0, 1),
            gravityDirection: .zero,
            rotationRate: .zero
        )

        _ = simulation.advance(input: input, deltaTime: 1.0 / 60.0)

        XCTAssertLessThan(simulation.state.velocity.z, 0)
    }

    func testSlowMotionDoesNotActivateSound() {
        let initial = ToyPhysicsState(
            position: SIMD3<Float>(1, 0, 0),
            velocity: SIMD3<Float>(0, 2, 0),
            ropeLength: 1,
            angularVelocity: .zero,
            tension: 1,
            activity: 0
        )
        var simulation = ToySimulation(state: initial, configuration: .inertialTesting)

        _ = simulation.advance(input: .zero, deltaTime: 1.0 / 240.0)

        XCTAssertEqual(simulation.state.activity, 0, accuracy: 0.001)
    }

    func testSlackRopeDoesNotPushToyOutward() {
        var configuration = ToyPhysicsConfiguration.live
        configuration.gravityMagnitude = 0
        configuration.motionAccelerationScale = 0
        configuration.airDrag = 0
        configuration.maximumStretchRatio = 10
        let initial = ToyPhysicsState(
            position: SIMD3<Float>(0.5, 0, 0),
            velocity: .zero,
            ropeLength: configuration.ropeLength,
            angularVelocity: .zero,
            tension: 0,
            activity: 0
        )
        var simulation = ToySimulation(state: initial, configuration: configuration)

        _ = simulation.advance(input: .zero, deltaTime: 0.5)

        XCTAssertEqual(simulation.state.position.x, initial.position.x, accuracy: 0.000_1)
        XCTAssertEqual(simulation.state.velocity, .zero)
    }

    func testStraightAlternatingShakeDoesNotCountARevolution() {
        var simulation = ToySimulation(configuration: .testing)
        var completedWahs = 0

        for frameIndex in 0..<600 {
            let direction: Float = frameIndex.isMultiple(of: 2) ? 1 : -1
            let input = MotionInput(
                anchorAcceleration: SIMD3<Float>(direction * 1.8, 0, 0),
                gravityDirection: SIMD3<Float>(0, -1, 0),
                rotationRate: .zero
            )
            completedWahs += simulation.advance(
                input: input,
                deltaTime: 1.0 / 120.0
            ).completedWahs
        }

        XCTAssertEqual(completedWahs, 0)
    }

    func testStationaryInputDoesNotFalseCountOverSixtySeconds() {
        var simulation = ToySimulation(configuration: .testing)
        var completedWahs = 0
        let input = MotionInput(
            anchorAcceleration: .zero,
            gravityDirection: SIMD3<Float>(0, -1, 0),
            rotationRate: .zero
        )

        for _ in 0..<(60 * 60) {
            completedWahs += simulation.advance(
                input: input,
                deltaTime: 1.0 / 60.0
            ).completedWahs
        }

        XCTAssertEqual(completedWahs, 0)
        XCTAssertLessThan(simulation.state.activity, 0.01)
    }
}
