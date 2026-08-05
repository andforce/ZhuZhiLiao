package com.azhegezhege.zhuzhiliao.rendering

import android.content.Context
import android.opengl.GLES30
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import com.azhegezhege.zhuzhiliao.earth.EarthBoundaryLoader
import com.azhegezhege.zhuzhiliao.earth.EarthCameraAngles
import com.azhegezhege.zhuzhiliao.earth.EarthCameraFocus
import com.azhegezhege.zhuzhiliao.earth.EarthGeometry
import com.azhegezhege.zhuzhiliao.math.Vec3
import com.azhegezhege.zhuzhiliao.math.Vec4
import com.azhegezhege.zhuzhiliao.network.EarthNode
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

class EarthRenderer(
    private val context: Context,
    private var onDetailChange: (Int) -> Unit,
    private var onSelect: (EarthNode?) -> Unit,
) : GLSurfaceView.Renderer {
    private lateinit var program: GlProgram
    private lateinit var sphere: GlMesh
    private lateinit var torus: GlMesh
    private lateinit var countries: GlLineMesh
    private lateinit var regions: GlLineMesh
    private var nodes: List<EarthNode> = emptyList()
    private var renderedNodes: List<EarthNode> = emptyList()
    private var serverClockOffsetMilliseconds = 0L
    private var localWahAt: Long? = null
    private var reduceMotion = false
    private var autoRotationEnabled = true
    private var yaw = EarthCameraFocus.INITIAL.yaw
    private var pitch = EarthCameraFocus.INITIAL.pitch
    private var cameraDistance = 3.25f
    private var width = 1
    private var height = 1
    private var lastFrameNanos = System.nanoTime()
    private var lastInteractionNanos = System.nanoTime()
    private var lastReportedDetail = -1
    private var appliedInitialFocus = false
    private var focusAnimation: FocusAnimation? = null
    private var latestViewProjection = GlMatrix.identity()
    private var latestGlobe = GlMatrix.identity()

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        program = GlProgram(ToyShaders.LIT_VERTEX, ToyShaders.LIT_FRAGMENT)
        sphere = GlMesh(MeshGenerator.sphere(latitudeSegments = 28, longitudeSegments = 40)).also { it.upload() }
        torus = GlMesh(MeshGenerator.torus(majorSegments = 48, minorSegments = 6)).also { it.upload() }
        countries = GlLineMesh(EarthBoundaryLoader.vertices(context, "ne_110m_admin_0_countries", 1.006f)).also { it.upload() }
        regions = GlLineMesh(EarthBoundaryLoader.vertices(context, "ne_110m_admin_1_states_provinces", 1.009f)).also { it.upload() }
        GLES30.glEnable(GLES30.GL_BLEND)
        GLES30.glBlendFunc(GLES30.GL_SRC_ALPHA, GLES30.GL_ONE_MINUS_SRC_ALPHA)
        GLES30.glEnable(GLES30.GL_DEPTH_TEST)
        GLES30.glDepthFunc(GLES30.GL_LEQUAL)
        GLES30.glLineWidth(1f)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        this.width = max(width, 1)
        this.height = max(height, 1)
        GLES30.glViewport(0, 0, this.width, this.height)
    }

    override fun onDrawFrame(gl: GL10?) {
        val now = System.nanoTime()
        val delta = ((now - lastFrameNanos) / 1_000_000_000.0).toFloat().coerceIn(0f, 0.05f)
        lastFrameNanos = now
        updateFocusAnimation(now)
        if (focusAnimation == null && autoRotationEnabled && !reduceMotion && now - lastInteractionNanos > 3_000_000_000L) {
            yaw += delta * 0.055f
        }
        updateSceneMatrices()

        GLES30.glClearColor(0.012f, 0.022f, 0.055f, 1f)
        GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT or GLES30.GL_DEPTH_BUFFER_BIT)
        GLES30.glEnable(GLES30.GL_DEPTH_TEST)
        GLES30.glDepthMask(true)
        GLES30.glEnable(GLES30.GL_CULL_FACE)
        GLES30.glCullFace(GLES30.GL_BACK)
        program.use()
        GLES30.glUniformMatrix4fv(program.uniform("uViewProjection"), 1, false, latestViewProjection, 0)
        GLES30.glUniform3f(program.uniform("uCoolLight"), 0.35f, 0.80f, 0.88f)
        GLES30.glUniform3f(program.uniform("uWarmLight"), 1f, 0.84f, 0.42f)

        draw(sphere, GlMatrix.multiply(latestGlobe, GlMatrix.scale(Vec3(2f, 2f, 2f))), Vec4(0.025f, 0.07f, 0.11f, 0.98f), 0.08f)
        GLES30.glDisable(GLES30.GL_CULL_FACE)
        drawLines(countries, Vec4(0.48f, 0.82f, 0.82f, 0.78f))
        if (cameraDistance < 3f) {
            val alpha = ((3f - cameraDistance) / 0.65f).coerceIn(0f, 1f) * 0.42f
            drawLines(regions, Vec4(0.36f, 0.67f, 0.70f, alpha))
        }
        GLES30.glEnable(GLES30.GL_CULL_FACE)
        renderedNodes = screenClusteredNodes()
        drawNodes(renderedNodes)
        reportDetailIfNeeded()
    }

    fun update(
        nodes: List<EarthNode>,
        serverClockOffsetMilliseconds: Long,
        localWahAt: Long?,
        reduceMotion: Boolean,
        autoRotationEnabled: Boolean,
    ) {
        this.nodes = nodes
        this.serverClockOffsetMilliseconds = serverClockOffsetMilliseconds
        this.localWahAt = localWahAt
        this.reduceMotion = reduceMotion
        this.autoRotationEnabled = autoRotationEnabled
        applyInitialFocusIfNeeded()
    }

    fun setAutoRotation(enabled: Boolean) {
        autoRotationEnabled = enabled
        lastInteractionNanos = System.nanoTime()
    }

    fun handlePan(deltaX: Float, deltaY: Float) {
        focusAnimation = null
        yaw += deltaX * 0.006f
        pitch = (pitch + deltaY * 0.005f).coerceIn(-PI.toFloat() / 2f, PI.toFloat() / 2f)
        lastInteractionNanos = System.nanoTime()
    }

    fun handleScale(scaleFactor: Float) {
        if (!scaleFactor.isFinite() || scaleFactor <= 0f) return
        focusAnimation = null
        cameraDistance = (cameraDistance / scaleFactor).coerceIn(1.72f, 4.25f)
        lastInteractionNanos = System.nanoTime()
        reportDetailIfNeeded()
    }

    fun handleTap(x: Float, y: Float, hitRadius: Float) {
        updateSceneMatrices()
        var best: EarthNode? = null
        var bestDistance = Float.MAX_VALUE
        for (node in renderedNodes) {
            val screen = projectedPoint(node) ?: continue
            val distance = hypot(screen.first - x, screen.second - y)
            if (distance < hitRadius && distance < bestDistance) {
                best = node
                bestDistance = distance
            }
        }
        onSelect(best)
    }

    private fun applyInitialFocusIfNeeded() {
        if (appliedInitialFocus) return
        val targetNode = EarthCameraFocus.preferredNode(nodes, EarthCameraAngles(yaw, pitch)) ?: return
        appliedInitialFocus = true
        val target = EarthCameraFocus.centeredAngles(targetNode)
        lastInteractionNanos = System.nanoTime()
        if (reduceMotion) {
            yaw = target.yaw
            pitch = target.pitch
        } else {
            focusAnimation = FocusAnimation(EarthCameraAngles(yaw, pitch), target, lastInteractionNanos)
        }
    }

    private fun updateFocusAnimation(now: Long) {
        val animation = focusAnimation ?: return
        if (reduceMotion) {
            yaw = animation.target.yaw
            pitch = animation.target.pitch
            focusAnimation = null
            return
        }
        val progress = ((now - animation.startedAt) / 650_000_000.0).toFloat().coerceIn(0f, 1f)
        val eased = 1f - (1f - progress).pow(3)
        val delta = atan2(sin(animation.target.yaw - animation.start.yaw), cos(animation.target.yaw - animation.start.yaw))
        yaw = animation.start.yaw + delta * eased
        pitch = animation.start.pitch + (animation.target.pitch - animation.start.pitch) * eased
        if (progress >= 1f) {
            yaw = animation.target.yaw
            pitch = animation.target.pitch
            focusAnimation = null
            lastInteractionNanos = now
        }
    }

    private fun updateSceneMatrices() {
        val projection = GlMatrix.perspective(0.72f, width.toFloat() / height, 0.1f, 20f)
        val view = GlMatrix.lookAt(Vec3(0f, 0f, cameraDistance), Vec3.ZERO, Vec3.UP)
        latestViewProjection = GlMatrix.multiply(projection, view)
        latestGlobe = GlMatrix.multiply(
            GlMatrix.rotation(Math.toDegrees(yaw.toDouble()).toFloat(), Vec3.UP),
            GlMatrix.rotation(Math.toDegrees(pitch.toDouble()).toFloat(), Vec3(1f, 0f, 0f)),
        )
    }

    private fun drawNodes(items: List<EarthNode>) {
        val serverNow = System.currentTimeMillis() + serverClockOffsetMilliseconds
        val localActiveUntil = localWahAt?.plus(120_000L)
        items.forEach { node ->
            val normal = EarthGeometry.spherePoint(node.latitude, node.longitude)
            val position = normal * 1.035f
            val scoreScale = (log10((node.displayedWahs + 1).toFloat()) * 0.010f + 0.026f).coerceIn(0.026f, 0.075f)
            val userScale = if (node.kind == EarthNode.Kind.CLUSTER) {
                min(scoreScale + log10((node.displayedUsers + 1).toFloat()) * 0.012f, 0.09f)
            } else scoreScale
            val visualScale = userScale * 0.1f
            val color = if (node.highlightsMe) Vec4(0.98f, 0.72f, 0.28f, 1f) else Vec4(0.36f, 0.93f, 0.86f, 0.94f)
            draw(
                sphere,
                GlMatrix.multiply(latestGlobe, GlMatrix.translation(position), GlMatrix.scale(Vec3.ONE * (visualScale * 2f))),
                color,
                0.55f,
            )

            var activeUntil = node.activeUntil
            if (node.highlightsMe && localActiveUntil != null) {
                activeUntil = max(activeUntil ?: 0L, localActiveUntil + serverClockOffsetMilliseconds)
            }
            if (activeUntil == null || activeUntil <= serverNow) return@forEach
            GLES30.glDepthMask(false)
            GLES30.glDisable(GLES30.GL_CULL_FACE)
            val offsets = if (reduceMotion) floatArrayOf(0.18f) else floatArrayOf(0f, 0.33f, 0.66f)
            offsets.forEach { offset ->
                val phase = if (reduceMotion) offset else (((serverNow % 2_800L + 2_800L) % 2_800L) / 2_800f + offset) % 1f
                val radius = (0.045f + phase * 0.18f) * 0.1f
                val alpha = if (reduceMotion) 0.42f else (1f - phase) * 0.48f
                draw(
                    torus,
                    GlMatrix.multiply(
                        latestGlobe,
                        GlMatrix.translation(position + normal * 0.008f),
                        GlMatrix.alignZ(normal),
                        GlMatrix.scale(Vec3.ONE * (radius * 2f)),
                    ),
                    color.copy(w = alpha),
                    0.8f,
                )
            }
            GLES30.glEnable(GLES30.GL_CULL_FACE)
            GLES30.glDepthMask(true)
        }
    }

    private fun screenClusteredNodes(): List<EarthNode> {
        if (nodes.size <= 1) return nodes
        val fixed = mutableListOf<EarthNode>()
        val buckets = linkedMapOf<Pair<Int, Int>, MutableList<EarthNode>>()
        val cellSize = 20f * context.resources.displayMetrics.density
        nodes.forEach { node ->
            if (node.kind != EarthNode.Kind.PLAYER || node.highlightsMe) {
                fixed += node
                return@forEach
            }
            val screen = projectedPoint(node)
            if (screen == null) {
                fixed += node
                return@forEach
            }
            val key = floor(screen.first / cellSize).toInt() to floor(screen.second / cellSize).toInt()
            buckets.getOrPut(key) { mutableListOf() } += node
        }
        buckets.forEach { (key, bucket) ->
            if (bucket.size == 1) {
                fixed += bucket
                return@forEach
            }
            var vector = Vec3.ZERO
            var wahs = 0
            var activeCount = 0
            var activeUntil: Long? = null
            bucket.forEach { node ->
                vector += EarthGeometry.spherePoint(node.latitude, node.longitude)
                wahs += node.displayedWahs
                node.activeUntil?.let { deadline ->
                    activeCount += 1
                    activeUntil = max(activeUntil ?: 0L, deadline)
                }
            }
            val normalized = vector.normalized(Vec3(0f, 0f, 1f))
            fixed += EarthNode(
                kind = EarthNode.Kind.CLUSTER,
                id = "screen:${key.first}:${key.second}:${bucket.size}",
                code = null,
                score = null,
                latitude = Math.toDegrees(asin(normalized.y).toDouble()),
                longitude = Math.toDegrees(atan2(normalized.z, -normalized.x).toDouble()),
                userCount = bucket.sumOf(EarthNode::displayedUsers),
                totalWahs = wahs,
                activeCount = activeCount,
                activeUntil = activeUntil,
                isMe = false,
                containsMe = false,
            )
        }
        return fixed
    }

    private fun projectedPoint(node: EarthNode): Pair<Float, Float>? {
        val point = EarthGeometry.spherePoint(node.latitude, node.longitude, 1.04f)
        val world = FloatArray(4)
        Matrix.multiplyMV(world, 0, latestGlobe, 0, floatArrayOf(point.x, point.y, point.z, 1f), 0)
        if (world[2] <= 0f) return null
        val clip = FloatArray(4)
        Matrix.multiplyMV(clip, 0, latestViewProjection, 0, world, 0)
        if (clip[3] <= 0f) return null
        val normalizedX = clip[0] / clip[3]
        val normalizedY = clip[1] / clip[3]
        return (normalizedX * 0.5f + 0.5f) * width to (0.5f - normalizedY * 0.5f) * height
    }

    private fun drawLines(mesh: GlLineMesh, color: Vec4) {
        setMaterial(latestGlobe, color, 0.35f)
        mesh.draw(color.w)
    }

    private fun draw(mesh: GlMesh, model: FloatArray, color: Vec4, emissive: Float) {
        setMaterial(model, color, emissive)
        mesh.draw()
    }

    private fun setMaterial(model: FloatArray, color: Vec4, emissive: Float) {
        GLES30.glUniformMatrix4fv(program.uniform("uModel"), 1, false, model, 0)
        GLES30.glUniform4fv(program.uniform("uBaseColor"), 1, color.toFloatArray(), 0)
        GLES30.glUniform2f(program.uniform("uMaterial"), 0f, emissive)
    }

    private fun reportDetailIfNeeded() {
        val detail = when {
            cameraDistance >= 3.75f -> 0
            cameraDistance >= 3.35f -> 1
            cameraDistance >= 2.70f -> 2
            cameraDistance >= 2.10f -> 3
            else -> 4
        }
        if (detail == lastReportedDetail) return
        lastReportedDetail = detail
        onDetailChange(detail)
    }

    private data class FocusAnimation(
        val start: EarthCameraAngles,
        val target: EarthCameraAngles,
        val startedAt: Long,
    )
}
