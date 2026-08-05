package com.azhegezhege.zhuzhiliao.math

import kotlin.math.sqrt

data class Quaternion(val x: Float, val y: Float, val z: Float, val w: Float) {
    operator fun times(other: Quaternion) = Quaternion(
        w * other.x + x * other.w + y * other.z - z * other.y,
        w * other.y - x * other.z + y * other.w + z * other.x,
        w * other.z + x * other.y - y * other.x + z * other.w,
        w * other.w - x * other.x - y * other.y - z * other.z,
    )

    fun conjugate() = Quaternion(-x, -y, -z, w)

    fun normalized(): Quaternion {
        val magnitude = sqrt(x * x + y * y + z * z + w * w)
        return if (magnitude > Vec3.EPSILON) {
            Quaternion(x / magnitude, y / magnitude, z / magnitude, w / magnitude)
        } else IDENTITY
    }

    fun act(vector: Vec3): Vec3 {
        val value = this * Quaternion(vector.x, vector.y, vector.z, 0f) * conjugate()
        return Vec3(value.x, value.y, value.z)
    }

    companion object { val IDENTITY = Quaternion(0f, 0f, 0f, 1f) }
}
