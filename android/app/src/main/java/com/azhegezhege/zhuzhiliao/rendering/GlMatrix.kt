package com.azhegezhege.zhuzhiliao.rendering

import android.opengl.Matrix
import com.azhegezhege.zhuzhiliao.math.Vec3
import kotlin.math.abs
import kotlin.math.acos

object GlMatrix {
    fun identity() = FloatArray(16).also { Matrix.setIdentityM(it, 0) }

    fun multiply(vararg matrices: FloatArray): FloatArray {
        if (matrices.isEmpty()) return identity()
        var result = matrices.first().copyOf()
        for (index in 1 until matrices.size) {
            val next = FloatArray(16)
            Matrix.multiplyMM(next, 0, result, 0, matrices[index], 0)
            result = next
        }
        return result
    }

    fun translation(value: Vec3) = identity().also { Matrix.translateM(it, 0, value.x, value.y, value.z) }
    fun scale(value: Vec3) = identity().also { Matrix.scaleM(it, 0, value.x, value.y, value.z) }
    fun rotation(degrees: Float, axis: Vec3) = identity().also {
        val normalized = axis.normalized(Vec3.UP)
        Matrix.rotateM(it, 0, degrees, normalized.x, normalized.y, normalized.z)
    }

    fun perspective(fieldOfViewRadians: Float, aspect: Float, near: Float, far: Float) =
        FloatArray(16).also {
            Matrix.perspectiveM(it, 0, Math.toDegrees(fieldOfViewRadians.toDouble()).toFloat(), aspect, near, far)
        }

    fun lookAt(eye: Vec3, target: Vec3, up: Vec3) = FloatArray(16).also {
        Matrix.setLookAtM(it, 0, eye.x, eye.y, eye.z, target.x, target.y, target.z, up.x, up.y, up.z)
    }

    fun basis(x: Vec3, y: Vec3, z: Vec3): FloatArray = floatArrayOf(
        x.x, x.y, x.z, 0f,
        y.x, y.y, y.z, 0f,
        z.x, z.y, z.z, 0f,
        0f, 0f, 0f, 1f,
    )

    fun segment(start: Vec3, end: Vec3, radius: Float): FloatArray {
        val delta = end - start
        val length = delta.length.coerceAtLeast(0.0001f)
        val y = delta / length
        val x = if (abs(y.y) > 0.999f) Vec3(1f, 0f, 0f) else Vec3.UP.cross(y).normalized(Vec3(1f, 0f, 0f))
        val z = x.cross(y).normalized(Vec3(0f, 0f, 1f))
        return multiply(
            translation((start + end) * 0.5f),
            basis(x, y, z),
            scale(Vec3(radius, length, radius)),
        )
    }

    fun alignZ(direction: Vec3): FloatArray {
        val target = direction.normalized(Vec3(0f, 0f, 1f))
        val source = Vec3(0f, 0f, 1f)
        val dot = source.dot(target).coerceIn(-1f, 1f)
        if (dot > 0.999_999f) return identity()
        if (dot < -0.999_999f) return rotation(180f, Vec3(1f, 0f, 0f))
        val axis = source.cross(target).normalized(Vec3.UP)
        return rotation(Math.toDegrees(acos(dot).toDouble()).toFloat(), axis)
    }
}
