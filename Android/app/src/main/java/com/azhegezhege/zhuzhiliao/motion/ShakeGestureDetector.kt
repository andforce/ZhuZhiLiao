package com.azhegezhege.zhuzhiliao.motion

import com.azhegezhege.zhuzhiliao.math.Vec3
import kotlin.math.exp
import kotlin.math.sqrt

data class ShakeGestureConfiguration(
    val accelerationThreshold: Float = 0.18f,
    val fullIntensityAcceleration: Float = 1f,
    val jerkThreshold: Float = 2f,
    val fullIntensityJerk: Float = 10f,
    val directionChangeDotThreshold: Float = 0.25f,
    val activationDirectionChanges: Int = 2,
    val activationWindow: Double = 0.65,
    val minimumDirectionChangeInterval: Double = 0.055,
    val idleTimeout: Double = 0.45,
    val attackTime: Float = 0.08f,
    val releaseTime: Float = 0.55f,
    val gyroscopeAxisThreshold: Float = 0.35f,
    val accelerationAxisThreshold: Float = 0.025f,
    val oppositeAxisDotThreshold: Float = -0.6f,
    val oppositeAxisHoldTime: Float = 0.30f,
)

class ShakeGestureDetector(
    val configuration: ShakeGestureConfiguration = ShakeGestureConfiguration(),
) {
    private var previousAcceleration: Vec3? = null
    private var previousTimestamp: Double? = null
    private var lastImpulseDirection: Vec3? = null
    private var lastDirectionChangeTimestamp: Double? = null
    private val directionChangeTimestamps = ArrayDeque<Double>()
    private var lastQualifiedTimestamp: Double? = null
    private var filteredIntensity = 0f
    private var orbitAxis = ShakeDrive.DEFAULT_ORBIT_AXIS
    private var hasInferredOrbitAxis = false
    private var directionConfidence = 0f
    private var oppositeAxisEvidenceTime = 0f
    private var lastDrive = ShakeDrive.INACTIVE

    fun process(acceleration: Vec3, rotationRate: Vec3, timestamp: Double): ShakeDrive {
        if (timestamp == previousTimestamp) return lastDrive
        val boundedAcceleration = acceleration.clamped(2.5f)
        val previousAcceleration = previousAcceleration
        val previousTimestamp = previousTimestamp
        if (previousAcceleration == null || previousTimestamp == null) {
            this.previousAcceleration = boundedAcceleration
            this.previousTimestamp = timestamp
            return lastDrive
        }

        val elapsed = timestamp - previousTimestamp
        if (elapsed < 0.001 || elapsed > 0.1) {
            resetTransientTracking(timestamp, boundedAcceleration)
            return lastDrive
        }

        val deltaTime = elapsed.toFloat()
        val accelerationMagnitude = boundedAcceleration.length
        val jerkMagnitude = ((boundedAcceleration - previousAcceleration) / deltaTime).length
        val isEnergetic = accelerationMagnitude >= configuration.accelerationThreshold &&
            jerkMagnitude >= configuration.jerkThreshold
        if (isEnergetic) {
            lastQualifiedTimestamp = timestamp
            registerDirectionChangeIfNeeded(boundedAcceleration, timestamp)
        }

        while (directionChangeTimestamps.isNotEmpty() &&
            timestamp - directionChangeTimestamps.first() > configuration.activationWindow
        ) {
            directionChangeTimestamps.removeFirst()
        }

        val wasActive = lastDrive.isActive
        val isActive = if (wasActive) {
            lastQualifiedTimestamp?.let { timestamp - it <= configuration.idleTimeout } ?: false
        } else {
            directionChangeTimestamps.size >= configuration.activationDirectionChanges
        }

        val instantaneousIntensity = motionIntensity(accelerationMagnitude, jerkMagnitude, isEnergetic)
        val responseTime = if (instantaneousIntensity > filteredIntensity) {
            configuration.attackTime
        } else configuration.releaseTime
        val response = if (responseTime > 0f) 1f - exp(-deltaTime / responseTime) else 1f
        filteredIntensity += (instantaneousIntensity - filteredIntensity) * response
        filteredIntensity = filteredIntensity.coerceIn(0f, 1f)

        val evidence = inferredAxis(previousAcceleration, boundedAcceleration, rotationRate)
        if (evidence != null) {
            updateOrbitAxis(evidence.first, evidence.second, wasActive, deltaTime)
        } else {
            directionConfidence *= exp(-deltaTime * 2f)
            oppositeAxisEvidenceTime = 0f
        }

        if (wasActive && !isActive) {
            directionChangeTimestamps.clear()
            lastImpulseDirection = null
            lastDirectionChangeTimestamp = null
        }

        lastDrive = ShakeDrive(filteredIntensity, isActive, orbitAxis, directionConfidence)
        this.previousAcceleration = boundedAcceleration
        this.previousTimestamp = timestamp
        return lastDrive
    }

    fun reset(preservingOrbitAxis: Boolean = false): ShakeDrive {
        val preservedAxis = orbitAxis
        val preservedHistory = hasInferredOrbitAxis
        previousAcceleration = null
        previousTimestamp = null
        lastImpulseDirection = null
        lastDirectionChangeTimestamp = null
        directionChangeTimestamps.clear()
        lastQualifiedTimestamp = null
        filteredIntensity = 0f
        directionConfidence = 0f
        oppositeAxisEvidenceTime = 0f
        orbitAxis = if (preservingOrbitAxis) preservedAxis else ShakeDrive.DEFAULT_ORBIT_AXIS
        hasInferredOrbitAxis = preservingOrbitAxis && preservedHistory
        lastDrive = ShakeDrive.inactive(orbitAxis)
        return lastDrive
    }

    private fun registerDirectionChangeIfNeeded(acceleration: Vec3, timestamp: Double) {
        val direction = acceleration.normalized()
        if (direction.lengthSquared == 0f) return
        val lastDirection = lastImpulseDirection
        if (lastDirection == null) {
            lastImpulseDirection = direction
            return
        }
        val interval = lastDirectionChangeTimestamp?.let { timestamp - it } ?: Double.POSITIVE_INFINITY
        if (lastDirection.dot(direction) > configuration.directionChangeDotThreshold ||
            interval < configuration.minimumDirectionChangeInterval
        ) return
        directionChangeTimestamps.addLast(timestamp)
        lastImpulseDirection = direction
        lastDirectionChangeTimestamp = timestamp
    }

    private fun motionIntensity(
        accelerationMagnitude: Float,
        jerkMagnitude: Float,
        isEnergetic: Boolean,
    ): Float {
        if (!isEnergetic) return 0f
        val accelerationLevel = smoothStep(
            configuration.accelerationThreshold,
            configuration.fullIntensityAcceleration,
            accelerationMagnitude,
        )
        val jerkLevel = smoothStep(configuration.jerkThreshold, configuration.fullIntensityJerk, jerkMagnitude)
        return sqrt(accelerationLevel * jerkLevel)
    }

    private fun inferredAxis(previous: Vec3, acceleration: Vec3, rotationRate: Vec3): Pair<Vec3, Float>? {
        val accelerationAxis = previous.cross(acceleration)
        val accelerationConfidence = smoothStep(
            configuration.accelerationAxisThreshold,
            0.30f,
            accelerationAxis.length,
        )
        val gyroscopeConfidence = smoothStep(
            configuration.gyroscopeAxisThreshold,
            3f,
            rotationRate.length,
        )
        return when {
            accelerationConfidence >= gyroscopeConfidence && accelerationConfidence > 0f ->
                accelerationAxis.normalized(orbitAxis) to accelerationConfidence
            gyroscopeConfidence > 0f -> rotationRate.normalized(orbitAxis) to gyroscopeConfidence
            else -> null
        }
    }

    private fun updateOrbitAxis(candidateValue: Vec3, confidence: Float, wasActive: Boolean, deltaTime: Float) {
        val candidate = candidateValue.normalized(orbitAxis)
        if (!wasActive) {
            orbitAxis = if (!hasInferredOrbitAxis || orbitAxis.dot(candidate) < 0f) {
                candidate
            } else {
                (orbitAxis * 0.82f + candidate * 0.18f).normalized(orbitAxis)
            }
            hasInferredOrbitAxis = true
            directionConfidence = confidence
            oppositeAxisEvidenceTime = 0f
            return
        }
        if (orbitAxis.dot(candidate) <= configuration.oppositeAxisDotThreshold && confidence >= 0.35f) {
            oppositeAxisEvidenceTime += deltaTime
            if (oppositeAxisEvidenceTime >= configuration.oppositeAxisHoldTime) {
                orbitAxis = candidate
                directionConfidence = confidence
                oppositeAxisEvidenceTime = 0f
            }
        } else {
            oppositeAxisEvidenceTime = 0f
            directionConfidence += (confidence - directionConfidence) * minOf(1f, deltaTime * 6f)
        }
    }

    private fun resetTransientTracking(timestamp: Double, acceleration: Vec3) {
        previousAcceleration = acceleration
        previousTimestamp = timestamp
        lastImpulseDirection = null
        lastDirectionChangeTimestamp = null
        directionChangeTimestamps.clear()
        lastQualifiedTimestamp = null
        filteredIntensity = 0f
        oppositeAxisEvidenceTime = 0f
        lastDrive = ShakeDrive.inactive(orbitAxis)
    }
}

private fun Vec3.clamped(maximumMagnitude: Float): Vec3 {
    val magnitude = length
    return if (magnitude > maximumMagnitude && magnitude > 0f) this * (maximumMagnitude / magnitude) else this
}

private fun smoothStep(edge0: Float, edge1: Float, value: Float): Float {
    if (edge1 <= edge0) return if (value >= edge1) 1f else 0f
    val fraction = ((value - edge0) / (edge1 - edge0)).coerceIn(0f, 1f)
    return fraction * fraction * (3f - 2f * fraction)
}
