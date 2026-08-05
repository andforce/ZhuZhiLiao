import Foundation
import simd

struct MotionInput: Equatable, Sendable {
    var anchorAcceleration: SIMD3<Float>
    var gravityDirection: SIMD3<Float>
    var rotationRate: SIMD3<Float>
    /// 网页版的鼠标/触摸输入：杆梢相对初始位置的目标位移。
    /// `nil` 表示杆梢保持当前位置，仅使用设备惯性输入。
    var anchorTarget: SIMD3<Float>? = nil
    /// 任意方向持续摇动产生的稳定切向助力；触摸模式始终传入 `.inactive`。
    var shakeDrive: ShakeDrive = .inactive

    static let zero = MotionInput(
        anchorAcceleration: .zero,
        gravityDirection: .zero,
        rotationRate: .zero
    )
}

struct ToyPhysicsState: Equatable, Sendable {
    /// 竹筒相对杆梢的位置。竹筒速度仍位于世界坐标中，与网页版一致。
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    var ropeLength: Float
    var angularVelocity: SIMD3<Float>
    var tension: Float
    var activity: Float
    /// 角速度方向在一段时间内保持一致的程度，防止往复摆动误发声。
    var orbitCoherence: Float = 0
    /// 杆梢相对初始场景锚点的位置。
    var anchorOffset: SIMD3<Float> = .zero
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
    var minimumShakeRPS: Float
    var maximumShakeRPS: Float
    var shakeDriveResponseTime: Float
    var maximumShakeAcceleration: Float
    var coherenceThreshold: Float

    static let live = ToyPhysicsConfiguration(
        ropeLength: 1.65,
        fixedTimeStep: 1 / 240,
        gravityMagnitude: 7.67,
        motionAccelerationScale: 21,
        ropeStiffness: 2_600,
        ropeDamping: 14,
        airDrag: 0.35,
        // 网页版不硬截断绳长，过伸完全由弹簧力拉回；保留字段只供
        // 测试或特殊配置设置数值安全上限。
        maximumStretchRatio: .greatestFiniteMagnitude,
        soundThresholdRPS: 1.1,
        soundRampRPS: 2.6,
        orbitQualityThreshold: 0.55,
        minimumShakeRPS: 1.2,
        maximumShakeRPS: 3.4,
        shakeDriveResponseTime: 0.35,
        maximumShakeAcceleration: 35,
        coherenceThreshold: 0.60
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
        orbitQualityThreshold: 0.65,
        minimumShakeRPS: 1.2,
        maximumShakeRPS: 3.4,
        shakeDriveResponseTime: 0.35,
        maximumShakeAcceleration: 35,
        coherenceThreshold: 0.60
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
    private var hasStableOrbitAxis = false
    private var lastDriveAxis: SIMD3<Float>?

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
        hasStableOrbitAxis = false
        lastDriveAxis = nil
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
        // 网页版不是把竹筒直接拖到指针下，而是让杆梢以 26/s 的一阶响应
        // 追随目标。先移动锚点，再保持竹筒的世界位置不变，就会自然产生
        // 绳子滞后、收紧和回摆。
        var anchorVelocity = SIMD3<Float>.zero
        if let target = input.anchorTarget {
            let previousAnchor = state.anchorOffset
            let response = 1 - exp(-timeStep * 26)
            state.anchorOffset += (target - state.anchorOffset) * response
            let anchorDelta = state.anchorOffset - previousAnchor
            state.position -= anchorDelta
            anchorVelocity = anchorDelta / timeStep
        }

        synchronizeDriveDirection(input.shakeDrive)

        let gravity = input.gravityDirection.normalized(or: .zero) * configuration.gravityMagnitude
        var acceleration = gravity
            - input.anchorAcceleration * configuration.motionAccelerationScale
            - state.velocity * configuration.airDrag
        acceleration += shakeAssistance(
            input.shakeDrive,
            anchorVelocity: anchorVelocity
        )

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

        let orbitQuality = updateDerivedState(
            anchorVelocity: anchorVelocity,
            preferredDriveAxis: input.shakeDrive.isActive
                ? input.shakeDrive.orbitAxis
                : nil,
            timeStep: timeStep
        )
        return updateRevolutionCount(
            orbitQuality: orbitQuality,
            timeStep: timeStep
        )
    }

    private mutating func synchronizeDriveDirection(_ drive: ShakeDrive) {
        guard drive.isActive else { return }
        let axis = drive.orbitAxis.normalized(or: ShakeDrive.defaultOrbitAxis)

        if let lastDriveAxis, simd_dot(lastDriveAxis, axis) < 0.5 {
            orbitCounter.reset()
            state.orbitCoherence = 0
            state.activity = 0
            stableOrbitAxis = axis
            hasStableOrbitAxis = true
        } else if lastDriveAxis == nil,
                  simd_length(state.angularVelocity) < 0.5 {
            stableOrbitAxis = axis
            hasStableOrbitAxis = true
        }
        lastDriveAxis = axis
    }

    private func shakeAssistance(
        _ drive: ShakeDrive,
        anchorVelocity: SIMD3<Float>
    ) -> SIMD3<Float> {
        guard drive.isActive else { return .zero }

        let axis = drive.orbitAxis.normalized(or: ShakeDrive.defaultOrbitAxis)
        let radiusDirection = state.position.normalized(or: SIMD3<Float>(0, -1, 0))
        var tangent = simd_cross(axis, radiusDirection)
        if simd_length_squared(tangent) < 0.000_001 {
            let fallback = abs(axis.y) < 0.9
                ? SIMD3<Float>(0, 1, 0)
                : SIMD3<Float>(1, 0, 0)
            tangent = simd_cross(axis, fallback)
        }
        tangent = tangent.normalized(or: SIMD3<Float>(1, 0, 0))

        let intensity = clamp(drive.intensity, 0, 1)
        let targetRPS = configuration.minimumShakeRPS
            + (configuration.maximumShakeRPS - configuration.minimumShakeRPS) * intensity
        let effectiveRadius = clamp(
            simd_length(state.position),
            configuration.ropeLength * 0.55,
            configuration.ropeLength
        )
        let targetTangentialSpeed = targetRPS * 2 * .pi * effectiveRadius
        let relativeVelocity = state.velocity - anchorVelocity
        let currentTangentialSpeed = simd_dot(relativeVelocity, tangent)
        let speedError = max(0, targetTangentialSpeed - currentTangentialSpeed)
        let requestedAcceleration = configuration.shakeDriveResponseTime > 0
            ? speedError / configuration.shakeDriveResponseTime
            : configuration.maximumShakeAcceleration
        let accelerationLimit = configuration.maximumShakeAcceleration
            * (0.35 + 0.65 * intensity)
        return tangent * min(requestedAcceleration, accelerationLimit)
    }

    @discardableResult
    private mutating func updateDerivedState(
        anchorVelocity: SIMD3<Float>,
        preferredDriveAxis: SIMD3<Float>?,
        timeStep: Float
    ) -> Float {
        let distanceSquared = simd_length_squared(state.position)
        let measuredAngularVelocity: SIMD3<Float>
        let relativeVelocity = state.velocity - anchorVelocity
        if distanceSquared > 0.000_001 {
            measuredAngularVelocity = simd_cross(state.position, relativeVelocity) / distanceSquared
        } else {
            measuredAngularVelocity = .zero
        }

        // 网页版用 9/s 的一阶滤波稳定绳方向角速度；向量形式让三维轨道
        // 也保留同样的起转、换向和松手余摆手感。
        state.angularVelocity += (measuredAngularVelocity - state.angularVelocity)
            * min(1, timeStep * 9)

        let measuredAngularSpeed = simd_length(measuredAngularVelocity)
        var targetCoherence: Float = 0
        if measuredAngularSpeed > 0.08 {
            let measuredAxis = measuredAngularVelocity / measuredAngularSpeed
            if !hasStableOrbitAxis {
                stableOrbitAxis = measuredAxis
                hasStableOrbitAxis = true
            } else {
                let referenceAxis = preferredDriveAxis?.normalized(or: stableOrbitAxis)
                    ?? stableOrbitAxis
                let alignment = simd_dot(measuredAxis, referenceAxis)
                if alignment >= 0.25 {
                    targetCoherence = smoothStep(
                        edge0: 0.65,
                        edge1: 0.98,
                        value: alignment
                    )
                    if preferredDriveAxis != nil {
                        stableOrbitAxis = referenceAxis
                    } else {
                        stableOrbitAxis = (stableOrbitAxis * 0.88 + measuredAxis * 0.12)
                            .normalized(or: measuredAxis)
                    }
                } else {
                    state.orbitCoherence = 0
                    orbitCounter.reset()
                    if alignment < -0.25 || preferredDriveAxis == nil {
                        stableOrbitAxis = measuredAxis
                    }
                }
            }
        }

        let coherenceResponse: Float = targetCoherence > state.orbitCoherence ? 4.5 : 12
        state.orbitCoherence += (targetCoherence - state.orbitCoherence)
            * min(1, timeStep * coherenceResponse)

        let angularSpeed = simd_length(state.angularVelocity)
        if measuredAngularSpeed <= 0.000_001, angularSpeed > 0.000_001 {
            state.angularVelocity = stableOrbitAxis * angularSpeed
        }

        let distance = simd_length(state.position)
        state.tension = clamp((distance / configuration.ropeLength - 0.88) / 0.12, 0, 1)
        let speed = simd_length(relativeVelocity)
        let crossMagnitude = simd_length(simd_cross(state.position, relativeVelocity))
        let orbitQuality = distance > 0.000_001 && speed > 0.000_001
            ? crossMagnitude / (distance * speed)
            : 0

        let rps = angularSpeed / (2 * .pi)
        let drive = clamp(
            (rps - configuration.soundThresholdRPS) / configuration.soundRampRPS,
            0,
            1
        )
        let qualityGate = smoothStep(
            edge0: configuration.orbitQualityThreshold,
            edge1: 0.92,
            value: orbitQuality
        )
        let coherenceGate = smoothStep(
            edge0: configuration.coherenceThreshold,
            edge1: 0.88,
            value: state.orbitCoherence
        )
        let targetActivity = pow(drive, 1.25)
            * state.tension
            * qualityGate
            * coherenceGate
        let response: Float = targetActivity > state.activity ? 10 : 3.2
        state.activity += (targetActivity - state.activity) * min(1, timeStep * response)
        phase += angularSpeed * timeStep * dominantAxisSign(state.angularVelocity)
        phase.formTruncatingRemainder(dividingBy: 2 * .pi)
        return orbitQuality
    }

    private mutating func updateRevolutionCount(
        orbitQuality: Float,
        timeStep: Float
    ) -> Int {
        let angularSpeed = simd_length(state.angularVelocity)
        return orbitCounter.update(
            angleDelta: angularSpeed * timeStep,
            axis: angularSpeed > 0.000_001 ? state.angularVelocity / angularSpeed : stableOrbitAxis,
            isQualified: state.activity > 0.3
                && state.tension > 0.8
                && state.orbitCoherence >= configuration.coherenceThreshold
                && orbitQuality > configuration.orbitQualityThreshold
        )
    }
}

/// 与网页 3D 层 `catenaryPoints` 相同的绳形。物理端点来自定步长模拟，
/// 绳中段只消费松弛量，因此收紧时立刻拉直，松绳时自然向下垂落。
enum WebRopeShape {
    static func points(
        anchor: SIMD3<Float>,
        bob: SIMD3<Float>,
        ropeLength: Float,
        count: Int = 25
    ) -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        update(
            &result,
            anchor: anchor,
            bob: bob,
            ropeLength: ropeLength,
            count: count
        )
        return result
    }

    static func update(
        _ points: inout [SIMD3<Float>],
        anchor: SIMD3<Float>,
        bob: SIMD3<Float>,
        ropeLength: Float,
        count: Int = 25
    ) {
        precondition(count >= 2)
        let slack = max(0, ropeLength - simd_distance(anchor, bob))
        let sag = slack * 0.55
        points.removeAll(keepingCapacity: true)
        points.reserveCapacity(count)

        for index in 0..<count {
            if index == 0 {
                points.append(anchor)
                continue
            }
            if index == count - 1 {
                points.append(bob)
                continue
            }
            let fraction = Float(index) / Float(count - 1)
            var point = simd_mix(
                anchor,
                bob,
                SIMD3<Float>(repeating: fraction)
            )
            point.y -= sag
                * sin(.pi * fraction)
                // 网页函数从竹筒端采样到杆梢端；这里数组方向相反，
                // 因此把原式 (1 - .25*t) 反向后使用。
                * (0.75 + 0.25 * fraction)
            points.append(point)
        }
    }
}

private func clamp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
    min(max(value, lower), upper)
}

private func dominantAxisSign(_ value: SIMD3<Float>) -> Float {
    let magnitude = abs(value)
    let dominant: Float
    if magnitude.x >= magnitude.y, magnitude.x >= magnitude.z {
        dominant = value.x
    } else if magnitude.y >= magnitude.z {
        dominant = value.y
    } else {
        dominant = value.z
    }
    return dominant < 0 ? -1 : 1
}

private func smoothStep(edge0: Float, edge1: Float, value: Float) -> Float {
    guard edge1 > edge0 else { return value >= edge1 ? 1 : 0 }
    let fraction = clamp((value - edge0) / (edge1 - edge0), 0, 1)
    return fraction * fraction * (3 - 2 * fraction)
}

private extension SIMD3 where Scalar == Float {
    func normalized(or fallback: SIMD3<Float>) -> SIMD3<Float> {
        let magnitude = simd_length(self)
        return magnitude > 0.000_001 ? self / magnitude : fallback
    }
}
