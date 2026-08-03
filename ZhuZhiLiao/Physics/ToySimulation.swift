import Foundation
import simd

struct MotionInput: Equatable, Sendable {
    var anchorAcceleration: SIMD3<Float>
    var gravityDirection: SIMD3<Float>
    var rotationRate: SIMD3<Float>

    static let zero = MotionInput(
        anchorAcceleration: .zero,
        gravityDirection: .zero,
        rotationRate: .zero
    )
}

struct ToyPhysicsState: Equatable, Sendable {
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    var ropeLength: Float
    var angularVelocity: SIMD3<Float>
    var tension: Float
    var activity: Float
}

struct ToyPhysicsConfiguration: Equatable, Sendable {
    var ropeLength: Float
    var fixedTimeStep: Float
    var gravityMagnitude: Float
    var motionAccelerationScale: Float
    var ropeStiffness: Float
    var ropeDamping: Float
    var airDrag: Float
    var maximumStretchRatio: Float
    var soundThresholdRPS: Float
    var soundRampRPS: Float
    var orbitQualityThreshold: Float

    static let live = ToyPhysicsConfiguration(
        ropeLength: 1.65,
        fixedTimeStep: 1 / 240,
        gravityMagnitude: 7.67,
        motionAccelerationScale: 18,
        ropeStiffness: 2_600,
        ropeDamping: 14,
        airDrag: 0.35,
        maximumStretchRatio: 1.12,
        soundThresholdRPS: 1.1,
        soundRampRPS: 2.6,
        orbitQualityThreshold: 0.65
    )

    static let testing = live

    static let inertialTesting = ToyPhysicsConfiguration(
        ropeLength: 1,
        fixedTimeStep: 1 / 240,
        gravityMagnitude: 0,
        motionAccelerationScale: 1,
        ropeStiffness: 0,
        ropeDamping: 0,
        airDrag: 0,
        maximumStretchRatio: 10,
        soundThresholdRPS: 1.1,
        soundRampRPS: 2.6,
        orbitQualityThreshold: 0.65
    )
}

struct SimulationFrame: Equatable, Sendable {
    var state: ToyPhysicsState
    var revolutionsPerSecond: Float
    var phase: Float
    var completedWahs: Int
}

struct ToySimulation: Sendable {
    private let configuration: ToyPhysicsConfiguration
    private var accumulatedTime: Double = 0
    private var orbitCounter = OrbitCounter()
    private var phase: Float = 0
    private var stableOrbitAxis = SIMD3<Float>(0, 0, 1)

    private(set) var state: ToyPhysicsState

    init(configuration: ToyPhysicsConfiguration = .live) {
        self.configuration = configuration
        state = ToyPhysicsState(
            position: SIMD3<Float>(0.06, -configuration.ropeLength * 0.92, 0),
            velocity: SIMD3<Float>(0.22, 0, 0),
            ropeLength: configuration.ropeLength,
            angularVelocity: .zero,
            tension: 0,
            activity: 0
        )
    }

    init(state: ToyPhysicsState, configuration: ToyPhysicsConfiguration) {
        self.state = state
        self.configuration = configuration
    }

    mutating func reset(gravityDirection: SIMD3<Float> = SIMD3<Float>(0, -1, 0)) {
        let direction = gravityDirection.normalized(or: SIMD3<Float>(0, -1, 0))
        state = ToyPhysicsState(
            position: direction * configuration.ropeLength * 0.92,
            velocity: SIMD3<Float>(0.22, 0, 0),
            ropeLength: configuration.ropeLength,
            angularVelocity: .zero,
            tension: 0,
            activity: 0
        )
        accumulatedTime = 0
        orbitCounter.reset()
        phase = 0
        stableOrbitAxis = SIMD3<Float>(0, 0, 1)
    }

    mutating func advance(input: MotionInput, deltaTime: TimeInterval) -> SimulationFrame {
        accumulatedTime += min(max(deltaTime, 0), 0.05)
        let step = Double(configuration.fixedTimeStep)
        var completedWahs = 0

        while accumulatedTime + 1e-8 >= step {
            completedWahs += integrate(input: input, timeStep: configuration.fixedTimeStep)
            accumulatedTime -= step
        }

        return SimulationFrame(
            state: state,
            revolutionsPerSecond: simd_length(state.angularVelocity) / (2 * .pi),
            phase: phase,
            completedWahs: completedWahs
        )
    }

    private mutating func integrate(input: MotionInput, timeStep: Float) -> Int {
        let gravity = input.gravityDirection.normalized(or: .zero) * configuration.gravityMagnitude
        var acceleration = gravity
            - input.anchorAcceleration * configuration.motionAccelerationScale
            - state.velocity * configuration.airDrag

        let distance = simd_length(state.position)
        if distance > configuration.ropeLength, distance > 0.000_001 {
            let direction = state.position / distance
            let radialVelocity = simd_dot(state.velocity, direction)
            let pull = max(
                0,
                configuration.ropeStiffness * (distance - configuration.ropeLength)
                    + configuration.ropeDamping * radialVelocity
            )
            acceleration -= direction * pull
        }

        state.velocity += acceleration * timeStep
        state.position += state.velocity * timeStep

        let maximumDistance = configuration.ropeLength * configuration.maximumStretchRatio
        let integratedDistance = simd_length(state.position)
        if integratedDistance > maximumDistance, integratedDistance > 0.000_001 {
            let direction = state.position / integratedDistance
            state.position = direction * maximumDistance
            let outwardSpeed = simd_dot(state.velocity, direction)
            if outwardSpeed > 0 {
                state.velocity -= direction * outwardSpeed
            }
        }

        updateDerivedState(timeStep: timeStep)
        return updateRevolutionCount(timeStep: timeStep)
    }

    private mutating func updateDerivedState(timeStep: Float) {
        let distanceSquared = simd_length_squared(state.position)
        if distanceSquared > 0.000_001 {
            state.angularVelocity = simd_cross(state.position, state.velocity) / distanceSquared
        } else {
            state.angularVelocity = .zero
        }

        let angularSpeed = simd_length(state.angularVelocity)
        if angularSpeed > 0.08 {
            let measuredAxis = state.angularVelocity / angularSpeed
            if simd_dot(measuredAxis, stableOrbitAxis) < 0 {
                stableOrbitAxis = measuredAxis
            } else {
                stableOrbitAxis = simd_normalize(stableOrbitAxis * 0.88 + measuredAxis * 0.12)
            }
        } else if angularSpeed > 0.000_001 {
            state.angularVelocity = stableOrbitAxis * angularSpeed
        }

        let distance = simd_length(state.position)
        state.tension = clamp((distance / configuration.ropeLength - 0.88) / 0.12, 0, 1)

        let rps = angularSpeed / (2 * .pi)
        let drive = clamp(
            (rps - configuration.soundThresholdRPS) / configuration.soundRampRPS,
            0,
            1
        )
        let targetActivity = pow(drive, 1.25) * state.tension
        let response: Float = targetActivity > state.activity ? 10 : 3.2
        state.activity += (targetActivity - state.activity) * min(1, timeStep * response)
        phase += angularSpeed * timeStep
        phase.formTruncatingRemainder(dividingBy: 2 * .pi)
    }

    private mutating func updateRevolutionCount(timeStep: Float) -> Int {
        let positionMagnitude = simd_length(state.position)
        let speed = simd_length(state.velocity)
        let crossMagnitude = simd_length(simd_cross(state.position, state.velocity))
        let orbitQuality = positionMagnitude > 0.000_001 && speed > 0.000_001
            ? crossMagnitude / (positionMagnitude * speed)
            : 0

        let angularSpeed = simd_length(state.angularVelocity)
        return orbitCounter.update(
            angleDelta: angularSpeed * timeStep,
            axis: angularSpeed > 0.000_001 ? state.angularVelocity / angularSpeed : stableOrbitAxis,
            isQualified: state.activity > 0.3
                && state.tension > 0.8
                && orbitQuality > configuration.orbitQualityThreshold
        )
    }
}

private func clamp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
    min(max(value, lower), upper)
}

private extension SIMD3 where Scalar == Float {
    func normalized(or fallback: SIMD3<Float>) -> SIMD3<Float> {
        let magnitude = simd_length(self)
        return magnitude > 0.000_001 ? self / magnitude : fallback
    }
}
