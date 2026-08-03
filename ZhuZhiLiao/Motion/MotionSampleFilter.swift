import Foundation
import simd

struct MotionFilterConfiguration: Equatable, Sendable {
    var deadZone: Float
    var maximumMagnitude: Float
    var smoothingFactor: Float

    static let live = MotionFilterConfiguration(
        deadZone: 0.03,
        maximumMagnitude: 2.5,
        smoothingFactor: 0.25
    )
}

struct MotionSampleFilter: Sendable {
    let configuration: MotionFilterConfiguration
    private(set) var filteredValue = SIMD3<Float>.zero
    private var lastTimestamp: TimeInterval?

    init(configuration: MotionFilterConfiguration = .live) {
        self.configuration = configuration
    }

    mutating func process(
        _ sample: SIMD3<Float>,
        timestamp: TimeInterval? = nil
    ) -> SIMD3<Float> {
        if let timestamp, timestamp == lastTimestamp {
            return filteredValue
        }

        let magnitude = simd_length(sample)
        let target: SIMD3<Float>

        if magnitude < configuration.deadZone {
            target = .zero
        } else if magnitude > configuration.maximumMagnitude, magnitude > 0 {
            target = sample * (configuration.maximumMagnitude / magnitude)
        } else {
            target = sample
        }

        let smoothing = min(max(configuration.smoothingFactor, 0), 1)
        filteredValue += (target - filteredValue) * smoothing
        lastTimestamp = timestamp
        return filteredValue
    }

    mutating func reset() {
        filteredValue = .zero
        lastTimestamp = nil
    }
}

struct ElbowPivotMotionConfiguration: Equatable, Sendable {
    var virtualArmLength: Float
    var angularSpeedDeadZone: Float
    var maximumAngularAcceleration: Float
    var maximumAssistMagnitude: Float
    var assistGain: Float
    var smoothingFactor: Float
    var maximumOutputMagnitude: Float

    static let live = ElbowPivotMotionConfiguration(
        virtualArmLength: 0.32,
        angularSpeedDeadZone: 0.16,
        maximumAngularAcceleration: 18,
        maximumAssistMagnitude: 0.85,
        assistGain: 0.82,
        smoothingFactor: 0.22,
        maximumOutputMagnitude: 2.5
    )
}

/// 把手机绕手肘转动的陀螺仪信号，换算成手部沿圆弧运动时的加速度。
///
/// 用户不必刻意用手腕画出完美圆圈。只要握住手机、以前臂长度为力臂转动，
/// 切向加速度 `alpha x radius` 与向心加速度 `omega x (omega x radius)` 就能
/// 补足 Core Motion 在线性加速度上容易被握持姿势削弱的部分。
struct ElbowPivotMotionFilter: Sendable {
    let configuration: ElbowPivotMotionConfiguration
    private var previousRotationRate: SIMD3<Float>?
    private var previousTimestamp: TimeInterval?
    private var filteredAssist = SIMD3<Float>.zero
    private var lastOutput = SIMD3<Float>.zero

    init(configuration: ElbowPivotMotionConfiguration = .live) {
        self.configuration = configuration
    }

    mutating func process(
        measuredAcceleration: SIMD3<Float>,
        rotationRate: SIMD3<Float>,
        pivotToPhoneDirection: SIMD3<Float>,
        timestamp: TimeInterval
    ) -> SIMD3<Float> {
        if timestamp == previousTimestamp {
            return lastOutput
        }

        let deltaTime = previousTimestamp.map { timestamp - $0 }
        let angularAcceleration: SIMD3<Float>
        if let previousRotationRate,
           let deltaTime,
           deltaTime > 0.001,
           deltaTime < 0.1 {
            angularAcceleration = (rotationRate - previousRotationRate) / Float(deltaTime)
        } else {
            angularAcceleration = .zero
        }

        let effectiveRotationRate = removingDeadZone(
            from: rotationRate,
            deadZone: configuration.angularSpeedDeadZone
        )
        let limitedAngularAcceleration = clamped(
            angularAcceleration,
            maximumMagnitude: configuration.maximumAngularAcceleration
        )
        let radius = normalized(
            pivotToPhoneDirection,
            fallback: SIMD3<Float>(0, 1, 0)
        ) * configuration.virtualArmLength

        let tangentialAcceleration = simd_cross(limitedAngularAcceleration, radius)
        let centripetalAcceleration = simd_cross(
            effectiveRotationRate,
            simd_cross(effectiveRotationRate, radius)
        )
        let gravityInMetersPerSecondSquared: Float = 9.80665
        let targetAssist = clamped(
            (tangentialAcceleration + centripetalAcceleration)
                / gravityInMetersPerSecondSquared
                * configuration.assistGain,
            maximumMagnitude: configuration.maximumAssistMagnitude
        )

        let smoothing = min(max(configuration.smoothingFactor, 0), 1)
        filteredAssist += (targetAssist - filteredAssist) * smoothing
        lastOutput = clamped(
            measuredAcceleration + filteredAssist,
            maximumMagnitude: configuration.maximumOutputMagnitude
        )
        previousRotationRate = rotationRate
        previousTimestamp = timestamp
        return lastOutput
    }

    mutating func reset() {
        previousRotationRate = nil
        previousTimestamp = nil
        filteredAssist = .zero
        lastOutput = .zero
    }
}

private func removingDeadZone(
    from value: SIMD3<Float>,
    deadZone: Float
) -> SIMD3<Float> {
    let magnitude = simd_length(value)
    guard magnitude > deadZone, magnitude > 0 else { return .zero }
    return value * ((magnitude - deadZone) / magnitude)
}

private func clamped(
    _ value: SIMD3<Float>,
    maximumMagnitude: Float
) -> SIMD3<Float> {
    let magnitude = simd_length(value)
    guard magnitude > maximumMagnitude, magnitude > 0 else { return value }
    return value * (maximumMagnitude / magnitude)
}

private func normalized(
    _ value: SIMD3<Float>,
    fallback: SIMD3<Float>
) -> SIMD3<Float> {
    let magnitude = simd_length(value)
    return magnitude > 0.000_001 ? value / magnitude : fallback
}
