package com.azhegezhege.zhuzhiliao.motion

import com.azhegezhege.zhuzhiliao.math.Vec3

data class MotionFilterConfiguration(
    val deadZone: Float = 0.03f,
    val maximumMagnitude: Float = 2.5f,
    val smoothingFactor: Float = 0.25f,
)

class MotionSampleFilter(
    val configuration: MotionFilterConfiguration = MotionFilterConfiguration(),
) {
    var filteredValue: Vec3 = Vec3.ZERO
        private set
    private var lastTimestamp: Double? = null

    fun process(sample: Vec3, timestamp: Double? = null): Vec3 {
        if (timestamp != null && timestamp == lastTimestamp) return filteredValue
        val magnitude = sample.length
        val target = when {
            magnitude < configuration.deadZone -> Vec3.ZERO
            magnitude > configuration.maximumMagnitude && magnitude > 0f ->
                sample * (configuration.maximumMagnitude / magnitude)
            else -> sample
        }
        val smoothing = configuration.smoothingFactor.coerceIn(0f, 1f)
        filteredValue += (target - filteredValue) * smoothing
        lastTimestamp = timestamp
        return filteredValue
    }

    fun reset() {
        filteredValue = Vec3.ZERO
        lastTimestamp = null
    }
}
