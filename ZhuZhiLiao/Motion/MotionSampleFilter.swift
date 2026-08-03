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

struct ShakeDrive: Equatable, Sendable {
    var intensity: Float
    var isActive: Bool
    var orbitAxis: SIMD3<Float>
    var directionConfidence: Float

    /// 从相机方向看，`-z` 对应屏幕上的顺时针运动。
    static let defaultOrbitAxis = SIMD3<Float>(0, 0, -1)
    static let inactive = ShakeDrive(
        intensity: 0,
        isActive: false,
        orbitAxis: defaultOrbitAxis,
        directionConfidence: 0
    )

    static func inactive(orbitAxis: SIMD3<Float>) -> ShakeDrive {
        ShakeDrive(
            intensity: 0,
            isActive: false,
            orbitAxis: normalized(orbitAxis, fallback: defaultOrbitAxis),
            directionConfidence: 0
        )
    }
}

struct ShakeGestureConfiguration: Equatable, Sendable {
    var accelerationThreshold: Float
    var fullIntensityAcceleration: Float
    var jerkThreshold: Float
    var fullIntensityJerk: Float
    var directionChangeDotThreshold: Float
    var activationDirectionChanges: Int
    var activationWindow: TimeInterval
    var minimumDirectionChangeInterval: TimeInterval
    var idleTimeout: TimeInterval
    var attackTime: Float
    var releaseTime: Float
    var gyroscopeAxisThreshold: Float
    var accelerationAxisThreshold: Float
    var oppositeAxisDotThreshold: Float
    var oppositeAxisHoldTime: Float

    static let live = ShakeGestureConfiguration(
        accelerationThreshold: 0.18,
        fullIntensityAcceleration: 1.0,
        jerkThreshold: 2.0,
        fullIntensityJerk: 10,
        directionChangeDotThreshold: 0.25,
        activationDirectionChanges: 2,
        activationWindow: 0.65,
        minimumDirectionChangeInterval: 0.055,
        idleTimeout: 0.45,
        attackTime: 0.08,
        releaseTime: 0.55,
        gyroscopeAxisThreshold: 0.35,
        accelerationAxisThreshold: 0.025,
        oppositeAxisDotThreshold: -0.6,
        oppositeAxisHoldTime: 0.30
    )
}

/// 把任意方向的连续往复摇动变成稳定、可控的旋转驱动力。
///
/// 单次冲击最多产生一次方向变化，不会激活。往复或画圆会在短窗口内产生
/// 多次显著方向变化；激活后，能量包络控制转速，陀螺仪和加速度轨迹只负责
/// 推断并锁定旋转轴，避免杂乱手势让竹筒频繁换向。
struct ShakeGestureDetector: Sendable {
    let configuration: ShakeGestureConfiguration

    private var previousAcceleration: SIMD3<Float>?
    private var previousTimestamp: TimeInterval?
    private var lastImpulseDirection: SIMD3<Float>?
    private var lastDirectionChangeTimestamp: TimeInterval?
    private var directionChangeTimestamps: [TimeInterval] = []
    private var lastQualifiedTimestamp: TimeInterval?
    private var filteredIntensity: Float = 0
    private var orbitAxis = ShakeDrive.defaultOrbitAxis
    private var hasInferredOrbitAxis = false
    private var directionConfidence: Float = 0
    private var oppositeAxisEvidenceTime: Float = 0
    private var lastDrive = ShakeDrive.inactive

    init(configuration: ShakeGestureConfiguration = .live) {
        self.configuration = configuration
    }

    mutating func process(
        acceleration: SIMD3<Float>,
        rotationRate: SIMD3<Float>,
        timestamp: TimeInterval
    ) -> ShakeDrive {
        if timestamp == previousTimestamp {
            return lastDrive
        }

        let boundedAcceleration = clamped(acceleration, maximumMagnitude: 2.5)
        guard let previousAcceleration, let previousTimestamp else {
            self.previousAcceleration = boundedAcceleration
            self.previousTimestamp = timestamp
            return lastDrive
        }

        let elapsed = timestamp - previousTimestamp
        guard elapsed >= 0.001, elapsed <= 0.1 else {
            resetTransientTracking(at: timestamp, acceleration: boundedAcceleration)
            return lastDrive
        }

        let deltaTime = Float(elapsed)
        let accelerationMagnitude = simd_length(boundedAcceleration)
        let jerk = (boundedAcceleration - previousAcceleration) / deltaTime
        let jerkMagnitude = simd_length(jerk)
        let isEnergetic = accelerationMagnitude >= configuration.accelerationThreshold
            && jerkMagnitude >= configuration.jerkThreshold

        if isEnergetic {
            lastQualifiedTimestamp = timestamp
            registerDirectionChangeIfNeeded(
                acceleration: boundedAcceleration,
                timestamp: timestamp
            )
        }

        directionChangeTimestamps.removeAll {
            timestamp - $0 > configuration.activationWindow
        }

        let wasActive = lastDrive.isActive
        let isActive: Bool
        if wasActive {
            isActive = lastQualifiedTimestamp.map {
                timestamp - $0 <= configuration.idleTimeout
            } ?? false
        } else {
            isActive = directionChangeTimestamps.count
                >= configuration.activationDirectionChanges
        }

        let instantaneousIntensity = motionIntensity(
            accelerationMagnitude: accelerationMagnitude,
            jerkMagnitude: jerkMagnitude,
            isEnergetic: isEnergetic
        )
        let responseTime = instantaneousIntensity > filteredIntensity
            ? configuration.attackTime
            : configuration.releaseTime
        let response = responseTime > 0
            ? 1 - exp(-deltaTime / responseTime)
            : 1
        filteredIntensity += (instantaneousIntensity - filteredIntensity) * response
        filteredIntensity = clamp(filteredIntensity, lower: 0, upper: 1)

        if let evidence = inferredAxis(
            previousAcceleration: previousAcceleration,
            acceleration: boundedAcceleration,
            rotationRate: rotationRate
        ) {
            updateOrbitAxis(
                with: evidence.axis,
                confidence: evidence.confidence,
                wasActive: wasActive,
                deltaTime: deltaTime
            )
        } else {
            directionConfidence *= exp(-deltaTime * 2)
            oppositeAxisEvidenceTime = 0
        }

        if wasActive, !isActive {
            directionChangeTimestamps.removeAll(keepingCapacity: true)
            lastImpulseDirection = nil
            lastDirectionChangeTimestamp = nil
        }

        lastDrive = ShakeDrive(
            intensity: filteredIntensity,
            isActive: isActive,
            orbitAxis: orbitAxis,
            directionConfidence: directionConfidence
        )
        self.previousAcceleration = boundedAcceleration
        self.previousTimestamp = timestamp
        return lastDrive
    }

    @discardableResult
    mutating func reset(preservingOrbitAxis: Bool = false) -> ShakeDrive {
        let preservedAxis = orbitAxis
        let preservedHistory = hasInferredOrbitAxis
        previousAcceleration = nil
        previousTimestamp = nil
        lastImpulseDirection = nil
        lastDirectionChangeTimestamp = nil
        directionChangeTimestamps.removeAll(keepingCapacity: true)
        lastQualifiedTimestamp = nil
        filteredIntensity = 0
        directionConfidence = 0
        oppositeAxisEvidenceTime = 0
        orbitAxis = preservingOrbitAxis ? preservedAxis : ShakeDrive.defaultOrbitAxis
        hasInferredOrbitAxis = preservingOrbitAxis && preservedHistory
        lastDrive = .inactive(orbitAxis: orbitAxis)
        return lastDrive
    }

    private mutating func registerDirectionChangeIfNeeded(
        acceleration: SIMD3<Float>,
        timestamp: TimeInterval
    ) {
        let direction = normalized(acceleration, fallback: .zero)
        guard simd_length_squared(direction) > 0 else { return }

        guard let lastImpulseDirection else {
            self.lastImpulseDirection = direction
            return
        }

        let interval = lastDirectionChangeTimestamp.map { timestamp - $0 } ?? .infinity
        guard simd_dot(lastImpulseDirection, direction)
                <= configuration.directionChangeDotThreshold,
              interval >= configuration.minimumDirectionChangeInterval else {
            return
        }

        directionChangeTimestamps.append(timestamp)
        self.lastImpulseDirection = direction
        lastDirectionChangeTimestamp = timestamp
    }

    private func motionIntensity(
        accelerationMagnitude: Float,
        jerkMagnitude: Float,
        isEnergetic: Bool
    ) -> Float {
        guard isEnergetic else { return 0 }
        let accelerationLevel = smoothStep(
            edge0: configuration.accelerationThreshold,
            edge1: configuration.fullIntensityAcceleration,
            value: accelerationMagnitude
        )
        let jerkLevel = smoothStep(
            edge0: configuration.jerkThreshold,
            edge1: configuration.fullIntensityJerk,
            value: jerkMagnitude
        )
        return sqrt(accelerationLevel * jerkLevel)
    }

    private func inferredAxis(
        previousAcceleration: SIMD3<Float>,
        acceleration: SIMD3<Float>,
        rotationRate: SIMD3<Float>
    ) -> (axis: SIMD3<Float>, confidence: Float)? {
        let accelerationAxis = simd_cross(previousAcceleration, acceleration)
        let accelerationAxisMagnitude = simd_length(accelerationAxis)
        let accelerationConfidence = smoothStep(
            edge0: configuration.accelerationAxisThreshold,
            edge1: 0.30,
            value: accelerationAxisMagnitude
        )

        let gyroscopeMagnitude = simd_length(rotationRate)
        let gyroscopeConfidence = smoothStep(
            edge0: configuration.gyroscopeAxisThreshold,
            edge1: 3.0,
            value: gyroscopeMagnitude
        )

        if accelerationConfidence >= gyroscopeConfidence,
           accelerationConfidence > 0 {
            return (
                normalized(accelerationAxis, fallback: orbitAxis),
                accelerationConfidence
            )
        }
        if gyroscopeConfidence > 0 {
            return (
                normalized(rotationRate, fallback: orbitAxis),
                gyroscopeConfidence
            )
        }
        return nil
    }

    private mutating func updateOrbitAxis(
        with candidate: SIMD3<Float>,
        confidence: Float,
        wasActive: Bool,
        deltaTime: Float
    ) {
        let candidate = normalized(candidate, fallback: orbitAxis)
        guard wasActive else {
            if !hasInferredOrbitAxis || simd_dot(orbitAxis, candidate) < 0 {
                orbitAxis = candidate
            } else {
                orbitAxis = normalized(
                    orbitAxis * 0.82 + candidate * 0.18,
                    fallback: orbitAxis
                )
            }
            hasInferredOrbitAxis = true
            directionConfidence = confidence
            oppositeAxisEvidenceTime = 0
            return
        }

        if simd_dot(orbitAxis, candidate) <= configuration.oppositeAxisDotThreshold,
           confidence >= 0.35 {
            oppositeAxisEvidenceTime += deltaTime
            if oppositeAxisEvidenceTime >= configuration.oppositeAxisHoldTime {
                orbitAxis = candidate
                directionConfidence = confidence
                oppositeAxisEvidenceTime = 0
            }
        } else {
            oppositeAxisEvidenceTime = 0
            directionConfidence += (confidence - directionConfidence)
                * min(1, deltaTime * 6)
        }
    }

    private mutating func resetTransientTracking(
        at timestamp: TimeInterval,
        acceleration: SIMD3<Float>
    ) {
        previousAcceleration = acceleration
        previousTimestamp = timestamp
        lastImpulseDirection = nil
        lastDirectionChangeTimestamp = nil
        directionChangeTimestamps.removeAll(keepingCapacity: true)
        lastQualifiedTimestamp = nil
        filteredIntensity = 0
        oppositeAxisEvidenceTime = 0
        lastDrive = .inactive(orbitAxis: orbitAxis)
    }
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

private func clamp(_ value: Float, lower: Float, upper: Float) -> Float {
    min(max(value, lower), upper)
}

private func smoothStep(edge0: Float, edge1: Float, value: Float) -> Float {
    guard edge1 > edge0 else { return value >= edge1 ? 1 : 0 }
    let fraction = clamp((value - edge0) / (edge1 - edge0), lower: 0, upper: 1)
    return fraction * fraction * (3 - 2 * fraction)
}
