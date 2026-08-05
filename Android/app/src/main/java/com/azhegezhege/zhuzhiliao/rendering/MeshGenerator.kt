package com.azhegezhege.zhuzhiliao.rendering

import com.azhegezhege.zhuzhiliao.math.Vec3
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin

object MeshGenerator {
    fun cylinder(segments: Int = 32) = frustum(0.5f, 0.5f, segments)

    fun frustum(bottomRadius: Float = 0.34f, topRadius: Float = 0.5f, segments: Int = 40): MeshData {
        val vertices = mutableListOf<Vertex>()
        val indices = mutableListOf<Short>()
        val slope = topRadius - bottomRadius
        for (segment in 0..segments) {
            val fraction = segment.toFloat() / segments
            val angle = fraction * FULL_TURN
            val radial = Vec3(cos(angle), 0f, sin(angle))
            val normal = Vec3(radial.x, -slope, radial.z).normalized()
            vertices += vertex(radial.x * bottomRadius, -0.5f, radial.z * bottomRadius, normal, fraction, 0f)
            vertices += vertex(radial.x * topRadius, 0.5f, radial.z * topRadius, normal, fraction, 1f)
        }
        for (segment in 0 until segments) {
            val lower = segment * 2
            add(indices, lower, lower + 1, lower + 2, lower + 1, lower + 3, lower + 2)
        }
        appendCap(0.5f, topRadius, Vec3.UP, segments, vertices, indices, true)
        appendCap(-0.5f, bottomRadius, Vec3(0f, -1f, 0f), segments, vertices, indices, false)
        return MeshData(vertices, indices)
    }

    fun hollowTube(
        bottomRadius: Float = 0.45f,
        topRadius: Float = 0.50f,
        wallThickness: Float = 0.095f,
        segments: Int = 48,
    ): MeshData {
        val vertices = mutableListOf<Vertex>()
        val indices = mutableListOf<Short>()
        val innerBottom = max(bottomRadius - wallThickness, 0.05f)
        val innerTop = max(topRadius - wallThickness, 0.05f)
        for (segment in 0..segments) {
            val fraction = segment.toFloat() / segments
            val angle = fraction * FULL_TURN
            val radial = Vec3(cos(angle), 0f, sin(angle))
            val outerNormal = Vec3(radial.x, -(topRadius - bottomRadius), radial.z).normalized()
            val innerNormal = -Vec3(radial.x, -(innerTop - innerBottom), radial.z).normalized()
            vertices += vertex(radial.x * bottomRadius, -0.5f, radial.z * bottomRadius, outerNormal, fraction, 0f)
            vertices += vertex(radial.x * topRadius, 0.5f, radial.z * topRadius, outerNormal, fraction, 1f)
            vertices += vertex(radial.x * innerBottom, -0.5f, radial.z * innerBottom, innerNormal, fraction, 0f, 1f)
            vertices += vertex(radial.x * innerTop, 0.5f, radial.z * innerTop, innerNormal, fraction, 1f, 1f)
        }
        for (segment in 0 until segments) {
            val base = segment * 4
            val next = base + 4
            add(indices, base, base + 1, next, base + 1, next + 1, next)
            add(indices, base + 2, next + 2, base + 3, base + 3, next + 2, next + 3)
        }
        listOf(
            Rim(-0.5f, bottomRadius, innerBottom, Vec3(0f, -1f, 0f), false),
            Rim(0.5f, topRadius, innerTop, Vec3.UP, true),
        ).forEach { rim ->
            val start = vertices.size
            for (segment in 0..segments) {
                val fraction = segment.toFloat() / segments
                val angle = fraction * FULL_TURN
                val x = cos(angle); val z = sin(angle)
                vertices += vertex(x * rim.outer, rim.y, z * rim.outer, rim.normal, (x + 1f) * 0.5f, (z + 1f) * 0.5f, 2f)
                vertices += vertex(x * rim.inner, rim.y, z * rim.inner, rim.normal, (x + 1f) * 0.5f, (z + 1f) * 0.5f, 2f)
            }
            for (segment in 0 until segments) {
                val outer = start + segment * 2
                val inner = outer + 1
                val nextOuter = outer + 2
                val nextInner = outer + 3
                if (rim.reverse) add(indices, outer, nextOuter, inner, inner, nextOuter, nextInner)
                else add(indices, outer, inner, nextOuter, inner, nextInner, nextOuter)
            }
        }
        return MeshData(vertices, indices)
    }

    fun wing(lengthSegments: Int = 24, widthSegments: Int = 12): MeshData {
        val vertices = mutableListOf<Vertex>()
        val indices = mutableListOf<Short>()
        val row = widthSegments + 1
        for (surface in 0..1) {
            val surfaceSign = if (surface == 0) 1f else -1f
            for (lengthIndex in 0..lengthSegments) {
                val v = lengthIndex.toFloat() / lengthSegments
                val leafProgress = v.pow(0.88f)
                val envelope = max(sin(PI.toFloat() * leafProgress), 0f).pow(0.64f) * (0.92f - v * 0.12f)
                for (widthIndex in 0..widthSegments) {
                    val u = widthIndex.toFloat() / widthSegments
                    val across = u * 2f - 1f
                    val width = envelope * if (across < 0f) 0.47f else 0.55f
                    val arch = sin(PI.toFloat() * v) * (1f - across * across) * 0.072f
                    val thickness = surfaceSign * 0.012f * max(envelope, 0.12f)
                    val normal = Vec3(-across * 0.20f, (v - 0.48f) * 0.10f, surfaceSign).normalized()
                    vertices += vertex(across * width + sin(PI.toFloat() * v) * 0.025f, 0.5f - v, arch + thickness, normal, u, v)
                }
            }
        }
        val surfaceCount = (lengthSegments + 1) * row
        for (surface in 0..1) for (lengthIndex in 0 until lengthSegments) for (widthIndex in 0 until widthSegments) {
            val a = surface * surfaceCount + lengthIndex * row + widthIndex
            val b = surface * surfaceCount + (lengthIndex + 1) * row + widthIndex
            if (surface == 0) add(indices, a, b, a + 1, a + 1, b, b + 1)
            else add(indices, a, a + 1, b, a + 1, b + 1, b)
        }
        return MeshData(vertices, indices)
    }

    fun sphere(latitudeSegments: Int = 18, longitudeSegments: Int = 24): MeshData {
        val vertices = mutableListOf<Vertex>(); val indices = mutableListOf<Short>()
        for (latitude in 0..latitudeSegments) {
            val v = latitude.toFloat() / latitudeSegments
            val phi = v * PI.toFloat()
            for (longitude in 0..longitudeSegments) {
                val u = longitude.toFloat() / longitudeSegments
                val theta = u * FULL_TURN
                val normal = Vec3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                vertices += vertex(normal.x * 0.5f, normal.y * 0.5f, normal.z * 0.5f, normal, u, v)
            }
        }
        val row = longitudeSegments + 1
        for (latitude in 0 until latitudeSegments) for (longitude in 0 until longitudeSegments) {
            val a = latitude * row + longitude; val b = (latitude + 1) * row + longitude
            add(indices, a, b, a + 1, a + 1, b, b + 1)
        }
        return MeshData(vertices, indices)
    }

    fun torus(majorSegments: Int = 40, minorSegments: Int = 8): MeshData {
        val vertices = mutableListOf<Vertex>(); val indices = mutableListOf<Short>()
        for (major in 0..majorSegments) {
            val u = major.toFloat() / majorSegments; val outerAngle = u * FULL_TURN
            for (minor in 0..minorSegments) {
                val v = minor.toFloat() / minorSegments; val innerAngle = v * FULL_TURN
                val radial = 0.5f + 0.035f * cos(innerAngle)
                val normal = Vec3(cos(innerAngle) * cos(outerAngle), cos(innerAngle) * sin(outerAngle), sin(innerAngle)).normalized()
                vertices += vertex(radial * cos(outerAngle), radial * sin(outerAngle), 0.035f * sin(innerAngle), normal, u, v)
            }
        }
        val row = minorSegments + 1
        for (major in 0 until majorSegments) for (minor in 0 until minorSegments) {
            val a = major * row + minor; val b = (major + 1) * row + minor
            add(indices, a, b, a + 1, a + 1, b, b + 1)
        }
        return MeshData(vertices, indices)
    }

    private fun appendCap(y: Float, radius: Float, normal: Vec3, segments: Int, vertices: MutableList<Vertex>, indices: MutableList<Short>, reverse: Boolean) {
        val center = vertices.size
        vertices += vertex(0f, y, 0f, normal)
        for (segment in 0..segments) {
            val fraction = segment.toFloat() / segments; val angle = fraction * FULL_TURN
            vertices += vertex(cos(angle) * radius, y, sin(angle) * radius, normal, (cos(angle) + 1f) * 0.5f, (sin(angle) + 1f) * 0.5f)
        }
        for (segment in 0 until segments) {
            val first = center + 1 + segment; val second = first + 1
            if (reverse) add(indices, center, second, first) else add(indices, center, first, second)
        }
    }

    private fun vertex(x: Float, y: Float, z: Float, n: Vec3, u: Float = 0f, v: Float = 0f, surface: Float = 0f) =
        Vertex(x, y, z, n.x, n.y, n.z, u, v, surface)
    private fun add(target: MutableList<Short>, vararg values: Int) = values.forEach { target += it.toShort() }
    private data class Rim(val y: Float, val outer: Float, val inner: Float, val normal: Vec3, val reverse: Boolean)
    private val FULL_TURN = (2.0 * PI).toFloat()
}
