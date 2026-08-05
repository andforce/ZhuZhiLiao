package com.azhegezhege.zhuzhiliao.physics

import com.azhegezhege.zhuzhiliao.math.Vec3
import com.azhegezhege.zhuzhiliao.motion.ShakeDrive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

data class MotionInput(
    val anchorAcceleration: Vec3,
    val gravityDirection: Vec3,
    val rotationRate: Vec3,
    val anchorTarget: Vec3? = null,
    val shakeDrive: ShakeDrive = ShakeDrive.INACTIVE,
) {
    companion object {
        val ZERO = MotionInput(Vec3.ZERO, Vec3.ZERO, Vec3.ZERO)
    }
}

data class ToyPhysicsState(
    var position: Vec3,
    var velocity: Vec3,
    var ropeLength: Float,
    var angularVelocity: Vec3,
    var tension: Float,
    var activity: Float,
    var orbitCoherence: Float = 0f,
    var anchorOffset: Vec3 = Vec3.ZERO,
)

data class ToyPhysicsConfiguration(
    val ropeLength: Float = 1.65f,
    val fixedTimeStep: Float = 1f / 240f,
    val gravityMagnitude: Float = 7.67f,
    val motionAccelerationScale: Float = 21f,
    val ropeStiffness: Float = 2_600f,
    val ropeDamping: Float = 14f,
    val airDrag: Float = 0.35f,
    val maximumStretchRatio: Float = Float.MAX_VALUE,
    val soundThresholdRPS: Float = 1.1f,
    val soundRampRPS: Float = 2.6f,
    val orbitQualityThreshold: Float = 0.55f,
    val minimumShakeRPS: Float = 1.2f,
    val maximumShakeRPS: Float = 3.4f,
    val shakeDriveResponseTime: Float = 0.35f,
    val maximumShakeAcceleration: Float = 35f,
    val coherenceThreshold: Float = 0.60f,
)

data class SimulationFrame(
    val state: ToyPhysicsState,
    val revolutionsPerSecond: Float,
    val phase: Float,
    val completedWahs: Int,
)

class ToySimulation(
    private val configuration: ToyPhysicsConfiguration = ToyPhysicsConfiguration(),
    initialState: ToyPhysicsState? = null,
) {
    private var accumulatedTime = 0.0
    private val orbitCounter = OrbitCounter()
    private var phase = 0f
    private var stableOrbitAxis = Vec3(0f, 0f, 1f)
    private var hasStableOrbitAxis = false
    private var lastDriveAxis: Vec3? = null

    var state = initialState ?: ToyPhysicsState(
        position = Vec3(0.06f, -configuration.ropeLength * 0.92f, 0f),
        velocity = Vec3(0.22f, 0f, 0f),
        ropeLength = configuration.ropeLength,
        angularVelocity = Vec3.ZERO,
        tension = 0f,
        activity = 0f,
    )
        private set

    fun reset(gravityDirection: Vec3 = Vec3(0f, -1f, 0f)) {
        val direction = gravityDirection.normalized(Vec3(0f, -1f, 0f))
        state = ToyPhysicsState(
            position = direction * configuration.ropeLength * 0.92f,
            velocity = Vec3(0.22f, 0f, 0f),
            ropeLength = configuration.ropeLength,
            angularVelocity = Vec3.ZERO,
            tension = 0f,
            activity = 0f,
        )
        accumulatedTime = 0.0
        orbitCounter.reset()
        phase = 0f
        stableOrbitAxis = Vec3(0f, 0f, 1f)
        hasStableOrbitAxis = false
        lastDriveAxis = null
    }

    fun advance(input: MotionInput, deltaTime: Double): SimulationFrame {
        accumulatedTime += deltaTime.coerceIn(0.0, 0.05)
        val step = configuration.fixedTimeStep.toDouble()
        var completedWahs = 0
        while (accumulatedTime + 1e-8 >= step) {
            completedWahs += integrate(input, configuration.fixedTimeStep)
            accumulatedTime -= step
        }
        return SimulationFrame(
            state = state.copy(),
            revolutionsPerSecond = state.angularVelocity.length / FULL_TURN,
            phase = phase,
            completedWahs = completedWahs,
        )
    }

    private fun integrate(input: MotionInput, timeStep: Float): Int {
        var anchorVelocity = Vec3.ZERO
        input.anchorTarget?.let { target ->
            val previousAnchor = state.anchorOffset
            val response = 1f - exp(-timeStep * 26f)
            state.anchorOffset += (target - state.anchorOffset) * response
            val anchorDelta = state.anchorOffset - previousAnchor
            state.position -= anchorDelta
            anchorVelocity = anchorDelta / timeStep
        }

        synchronizeDriveDirection(input.shakeDrive)
        val gravity = input.gravityDirection.normalized(Vec3.ZERO) * configuration.gravityMagnitude
        var acceleration = gravity - input.anchorAcceleration * configuration.motionAccelerationScale -
            state.velocity * configuration.airDrag
        acceleration += shakeAssistance(input.shakeDrive, anchorVelocity)

        val distance = state.position.length
        if (distance > configuration.ropeLength && distance > Vec3.EPSILON) {
            val direction = state.position / distance
            val radialVelocity = state.velocity.dot(direction)
            val pull = max(
                0f,
                configuration.ropeStiffness * (distance - configuration.ropeLength) +
                    configuration.ropeDamping * radialVelocity,
            )
            acceleration -= direction * pull
        }

        state.velocity += acceleration * timeStep
        state.position += state.velocity * timeStep

        val maximumDistance = configuration.ropeLength * configuration.maximumStretchRatio
        val integratedDistance = state.position.length
        if (integratedDistance > maximumDistance && integratedDistance > Vec3.EPSILON) {
            val direction = state.position / integratedDistance
            state.position = direction * maximumDistance
            val outwardSpeed = state.velocity.dot(direction)
            if (outwardSpeed > 0f) state.velocity -= direction * outwardSpeed
        }

        val orbitQuality = updateDerivedState(
            anchorVelocity,
            input.shakeDrive.orbitAxis.takeIf { input.shakeDrive.isActive },
            timeStep,
        )
        return updateRevolutionCount(orbitQuality, timeStep)
    }

    private fun synchronizeDriveDirection(drive: ShakeDrive) {
        if (!drive.isActive) return
        val axis = drive.orbitAxis.normalized(ShakeDrive.DEFAULT_ORBIT_AXIS)
        val previous = lastDriveAxis
        if (previous != null && previous.dot(axis) < 0.5f) {
            orbitCounter.reset()
            state.orbitCoherence = 0f
            state.activity = 0f
            stableOrbitAxis = axis
            hasStableOrbitAxis = true
        } else if (previous == null && state.angularVelocity.length < 0.5f) {
            stableOrbitAxis = axis
            hasStableOrbitAxis = true
        }
        lastDriveAxis = axis
    }

    private fun shakeAssistance(drive: ShakeDrive, anchorVelocity: Vec3): Vec3 {
        if (!drive.isActive) return Vec3.ZERO
        val axis = drive.orbitAxis.normalized(ShakeDrive.DEFAULT_ORBIT_AXIS)
        val radiusDirection = state.position.normalized(Vec3(0f, -1f, 0f))
        var tangent = axis.cross(radiusDirection)
        if (tangent.lengthSquared < Vec3.EPSILON) {
            tangent = axis.cross(if (abs(axis.y) < 0.9f) Vec3.UP else Vec3(1f, 0f, 0f))
        }
        tangent = tangent.normalized(Vec3(1f, 0f, 0f))

        val intensity = drive.intensity.coerceIn(0f, 1f)
        val targetRps = configuration.minimumShakeRPS +
            (configuration.maximumShakeRPS - configuration.minimumShakeRPS) * intensity
        val effectiveRadius = state.position.length.coerceIn(
            configuration.ropeLength * 0.55f,
            configuration.ropeLength,
        )
        val targetTangentialSpeed = targetRps * FULL_TURN * effectiveRadius
        val relativeVelocity = state.velocity - anchorVelocity
        val currentTangentialSpeed = relativeVelocity.dot(tangent)
        val speedError = max(0f, targetTangentialSpeed - currentTangentialSpeed)
        val requestedAcceleration = if (configuration.shakeDriveResponseTime > 0f) {
            speedError / configuration.shakeDriveResponseTime
        } else {
            configuration.maximumShakeAcceleration
        }
        val accelerationLimit = configuration.maximumShakeAcceleration * (0.35f + 0.65f * intensity)
        return tangent * min(requestedAcceleration, accelerationLimit)
    }

    private fun updateDerivedState(
        anchorVelocity: Vec3,
        preferredDriveAxis: Vec3?,
        timeStep: Float,
    ): Float {
        val distanceSquared = state.position.lengthSquared
        val relativeVelocity = state.velocity - anchorVelocity
        val measuredAngularVelocity = if (distanceSquared > Vec3.EPSILON) {
            state.position.cross(relativeVelocity) / distanceSquared
        } else Vec3.ZERO

        state.angularVelocity += (measuredAngularVelocity - state.angularVelocity) * min(1f, timeStep * 9f)
        val measuredAngularSpeed = measuredAngularVelocity.length
        var targetCoherence = 0f
        if (measuredAngularSpeed > 0.08f) {
            val measuredAxis = measuredAngularVelocity / measuredAngularSpeed
            if (!hasStableOrbitAxis) {
                stableOrbitAxis = measuredAxis
                hasStableOrbitAxis = true
            } else {
                val referenceAxis = preferredDriveAxis?.normalized(stableOrbitAxis) ?: stableOrbitAxis
                val alignment = measuredAxis.dot(referenceAxis)
                if (alignment >= 0.25f) {
                    targetCoherence = smoothStep(0.65f, 0.98f, alignment)
                    stableOrbitAxis = if (preferredDriveAxis != null) {
                        referenceAxis
                    } else {
                        (stableOrbitAxis * 0.88f + measuredAxis * 0.12f).normalized(measuredAxis)
                    }
                } else {
                    state.orbitCoherence = 0f
                    orbitCounter.reset()
                    if (alignment < -0.25f || preferredDriveAxis == null) stableOrbitAxis = measuredAxis
                }
            }
        }

        val coherenceResponse = if (targetCoherence > state.orbitCoherence) 4.5f else 12f
        state.orbitCoherence += (targetCoherence - state.orbitCoherence) * min(1f, timeStep * coherenceResponse)

        val angularSpeed = state.angularVelocity.length
        if (measuredAngularSpeed <= Vec3.EPSILON && angularSpeed > Vec3.EPSILON) {
            state.angularVelocity = stableOrbitAxis * angularSpeed
        }

        val distance = state.position.length
        state.tension = ((distance / configuration.ropeLength - 0.88f) / 0.12f).coerceIn(0f, 1f)
        val speed = relativeVelocity.length
        val crossMagnitude = state.position.cross(relativeVelocity).length
        val orbitQuality = if (distance > Vec3.EPSILON && speed > Vec3.EPSILON) {
            crossMagnitude / (distance * speed)
        } else 0f

        val rps = angularSpeed / FULL_TURN
        val drive = ((rps - configuration.soundThresholdRPS) / configuration.soundRampRPS).coerceIn(0f, 1f)
        val qualityGate = smoothStep(configuration.orbitQualityThreshold, 0.92f, orbitQuality)
        val coherenceGate = smoothStep(configuration.coherenceThreshold, 0.88f, state.orbitCoherence)
        val targetActivity = drive.pow(1.25f) * state.tension * qualityGate * coherenceGate
        val response = if (targetActivity > state.activity) 10f else 3.2f
        state.activity += (targetActivity - state.activity) * min(1f, timeStep * response)
        phase += angularSpeed * timeStep * dominantAxisSign(state.angularVelocity)
        phase %= FULL_TURN
        return orbitQuality
    }

    private fun updateRevolutionCount(orbitQuality: Float, timeStep: Float): Int {
        val angularSpeed = state.angularVelocity.length
        return orbitCounter.update(
            angleDelta = angularSpeed * timeStep,
            axis = if (angularSpeed > Vec3.EPSILON) state.angularVelocity / angularSpeed else stableOrbitAxis,
            isQualified = state.activity > 0.3f && state.tension > 0.8f &&
                state.orbitCoherence >= configuration.coherenceThreshold &&
                orbitQuality > configuration.orbitQualityThreshold,
        )
    }

    companion object {
        val FULL_TURN = (2.0 * PI).toFloat()
    }
}

object WebRopeShape {
    fun points(anchor: Vec3, bob: Vec3, ropeLength: Float, count: Int = 25): List<Vec3> {
        require(count >= 2)
        val slack = max(0f, ropeLength - anchor.distance(bob))
        val sag = slack * 0.55f
        return List(count) { index ->
            when (index) {
                0 -> anchor
                count - 1 -> bob
                else -> {
                    val fraction = index.toFloat() / (count - 1).toFloat()
                    val point = anchor + (bob - anchor) * fraction
                    point.copy(y = point.y - sag * sin(PI.toFloat() * fraction) * (0.75f + 0.25f * fraction))
                }
            }
        }
    }
}

private fun dominantAxisSign(value: Vec3): Float {
    val dominant = when {
        abs(value.x) >= abs(value.y) && abs(value.x) >= abs(value.z) -> value.x
        abs(value.y) >= abs(value.z) -> value.y
        else -> value.z
    }
    return if (dominant < 0f) -1f else 1f
}

private fun smoothStep(edge0: Float, edge1: Float, value: Float): Float {
    if (edge1 <= edge0) return if (value >= edge1) 1f else 0f
    val fraction = ((value - edge0) / (edge1 - edge0)).coerceIn(0f, 1f)
    return fraction * fraction * (3f - 2f * fraction)
}
