package com.azhegezhege.zhuzhiliao.earth

import com.azhegezhege.zhuzhiliao.math.Vec3
import com.azhegezhege.zhuzhiliao.network.EarthNode
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

data class EarthCameraAngles(val yaw: Float, val pitch: Float)

object EarthGeometry {
    fun spherePoint(latitude: Double, longitude: Double, radius: Float = 1f): Vec3 {
        val latitudeRadians = (latitude * PI / 180.0).toFloat()
        val longitudeRadians = (longitude * PI / 180.0).toFloat()
        val latitudeRadius = cos(latitudeRadians)
        return Vec3(
            -latitudeRadius * cos(longitudeRadians),
            sin(latitudeRadians),
            latitudeRadius * sin(longitudeRadians),
        ) * radius
    }

    fun rotated(point: Vec3, angles: EarthCameraAngles): Vec3 {
        val pitchCos = cos(angles.pitch)
        val pitchSin = sin(angles.pitch)
        val pitched = Vec3(
            point.x,
            point.y * pitchCos - point.z * pitchSin,
            point.y * pitchSin + point.z * pitchCos,
        )
        val yawCos = cos(angles.yaw)
        val yawSin = sin(angles.yaw)
        return Vec3(
            pitched.x * yawCos + pitched.z * yawSin,
            pitched.y,
            -pitched.x * yawSin + pitched.z * yawCos,
        )
    }
}

object EarthCameraFocus {
    val INITIAL = EarthCameraAngles(yaw = -1.35f, pitch = 0.18f)

    fun preferredNode(nodes: List<EarthNode>, angles: EarthCameraAngles): EarthNode? =
        nodes.firstOrNull(EarthNode::highlightsMe) ?: nodes.maxByOrNull { frontDepth(it, angles) }

    fun centeredAngles(node: EarthNode): EarthCameraAngles {
        val point = EarthGeometry.spherePoint(node.latitude, node.longitude)
        var pitch = atan2(point.y, point.z)
        if (pitch > PI.toFloat() / 2f) pitch -= PI.toFloat()
        else if (pitch < -PI.toFloat() / 2f) pitch += PI.toFloat()

        val pitchedZ = point.y * sin(pitch) + point.z * cos(pitch)
        val yaw = atan2(-point.x, pitchedZ)
        return EarthCameraAngles(yaw, pitch)
    }

    fun frontDepth(node: EarthNode, angles: EarthCameraAngles): Float =
        EarthGeometry.rotated(EarthGeometry.spherePoint(node.latitude, node.longitude), angles).z
}
