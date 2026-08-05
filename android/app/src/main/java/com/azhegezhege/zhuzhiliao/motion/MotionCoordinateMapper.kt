package com.azhegezhege.zhuzhiliao.motion

import com.azhegezhege.zhuzhiliao.math.Quaternion
import com.azhegezhege.zhuzhiliao.math.Vec3

internal object MotionCoordinateMapper {
    val DEFAULT_SENSOR_GRAVITY = Vec3(0f, 1f, 0f)

    fun sceneGravity(sensorGravity: Vec3, deviceToCalibratedScene: Quaternion): Vec3 =
        // Android 的重力传感器静止时与加速度计同向，表示设备受到的支撑力；
        // 物理模拟需要相反的自由落体加速度方向，语义与 Core Motion gravity 一致。
        deviceToCalibratedScene.act(-sensorGravity)
}
