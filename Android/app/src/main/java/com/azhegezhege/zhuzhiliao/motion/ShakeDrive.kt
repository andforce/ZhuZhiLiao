package com.azhegezhege.zhuzhiliao.motion

import com.azhegezhege.zhuzhiliao.math.Vec3

data class ShakeDrive(
    val intensity: Float,
    val isActive: Boolean,
    val orbitAxis: Vec3,
    val directionConfidence: Float,
) {
    companion object {
        val DEFAULT_ORBIT_AXIS = Vec3(0f, 0f, -1f)
        val INACTIVE = ShakeDrive(0f, false, DEFAULT_ORBIT_AXIS, 0f)

        fun inactive(orbitAxis: Vec3) = ShakeDrive(
            intensity = 0f,
            isActive = false,
            orbitAxis = orbitAxis.normalized(DEFAULT_ORBIT_AXIS),
            directionConfidence = 0f,
        )
    }
}
