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
}

