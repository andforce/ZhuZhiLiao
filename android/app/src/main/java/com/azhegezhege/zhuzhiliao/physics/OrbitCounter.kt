package com.azhegezhege.zhuzhiliao.physics

import com.azhegezhege.zhuzhiliao.math.Vec3
import kotlin.math.PI

class OrbitCounter {
    private var accumulatedAngle = 0f
    private var stableAxis: Vec3? = null

    fun reset() {
        accumulatedAngle = 0f
        stableAxis = null
    }

    fun update(angleDelta: Float, axis: Vec3, isQualified: Boolean): Int {
        val axisMagnitude = axis.length
        if (!isQualified || angleDelta <= 0f || axisMagnitude <= Vec3.EPSILON) {
            reset()
            return 0
        }

        val measuredAxis = axis / axisMagnitude
        val previous = stableAxis
        if (previous != null) {
            if (previous.dot(measuredAxis) < 0.75f) {
                accumulatedAngle = 0f
                stableAxis = measuredAxis
                return 0
            }
            stableAxis = (previous * 0.9f + measuredAxis * 0.1f).normalized(measuredAxis)
        } else {
            stableAxis = measuredAxis
        }

        val fullTurn = (2.0 * PI).toFloat()
        accumulatedAngle += angleDelta
        if (accumulatedAngle < fullTurn) return 0
        val completed = (accumulatedAngle / fullTurn).toInt()
        accumulatedAngle %= fullTurn
        return completed
    }
}
