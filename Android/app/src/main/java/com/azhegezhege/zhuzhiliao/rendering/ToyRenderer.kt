package com.azhegezhege.zhuzhiliao.rendering

import android.opengl.GLES30
import android.opengl.GLSurfaceView
import com.azhegezhege.zhuzhiliao.ExperienceCoordinator
import com.azhegezhege.zhuzhiliao.RenderSnapshot
import com.azhegezhege.zhuzhiliao.ToySceneLayout
import com.azhegezhege.zhuzhiliao.math.Vec3
import com.azhegezhege.zhuzhiliao.math.Vec4
import com.azhegezhege.zhuzhiliao.physics.WebRopeShape
import com.azhegezhege.zhuzhiliao.ui.SeasonPalette
import com.azhegezhege.zhuzhiliao.ui.SeasonTheme
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

class ToyRenderer(
    private val coordinator: ExperienceCoordinator,
    initialTheme: SeasonTheme,
) : GLSurfaceView.Renderer {
    private lateinit var backgroundProgram: GlProgram
    private lateinit var litProgram: GlProgram
    private lateinit var cylinder: GlMesh
    private lateinit var bambooTube: GlMesh
    private lateinit var wing: GlMesh
    private lateinit var sphere: GlMesh
    private lateinit var torus: GlMesh
    private val emptyVao = IntArray(1)
    private val ropeVao = IntArray(1)
    private val ropeVbo = IntArray(1)
    private var width = 1
    private var height = 1
    private var sourceTheme = initialTheme
    private var targetTheme = initialTheme
    private var transitionStarted = 0L
    private var transitionDuration = 0L
    private var stableBodyTangent = Vec3(0f, 0f, 1f)
    private val wingAngles = floatArrayOf(0.08f, 0.08f)
    private val wingVelocities = floatArrayOf(0f, 0f)
    private var lastEffectsTime: Float? = null
    private val trail = ArrayDeque<Vec3>()
    private val ripples = mutableListOf<Ripple>()
    private var lastRippleTime = 0f

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        backgroundProgram = GlProgram(ToyShaders.BACKGROUND_VERTEX, ToyShaders.BACKGROUND_FRAGMENT)
        litProgram = GlProgram(ToyShaders.LIT_VERTEX, ToyShaders.LIT_FRAGMENT)
        cylinder = GlMesh(MeshGenerator.cylinder()).also { it.upload() }
        bambooTube = GlMesh(MeshGenerator.hollowTube()).also { it.upload() }
        wing = GlMesh(MeshGenerator.wing()).also { it.upload() }
        sphere = GlMesh(MeshGenerator.sphere()).also { it.upload() }
        torus = GlMesh(MeshGenerator.torus()).also { it.upload() }
        GLES30.glGenVertexArrays(1, emptyVao, 0)
        GLES30.glGenVertexArrays(1, ropeVao, 0)
        GLES30.glGenBuffers(1, ropeVbo, 0)
        GLES30.glBindVertexArray(ropeVao[0])
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, ropeVbo[0])
        listOf(0 to 0, 1 to 3, 2 to 6).forEach { (location, offset) ->
            GLES30.glEnableVertexAttribArray(location)
            GLES30.glVertexAttribPointer(location, 3, GLES30.GL_FLOAT, false, GlMesh.STRIDE_BYTES, offset * 4)
        }
        GLES30.glBindVertexArray(0)
        GLES30.glEnable(GLES30.GL_BLEND)
        GLES30.glBlendFunc(GLES30.GL_SRC_ALPHA, GLES30.GL_ONE_MINUS_SRC_ALPHA)
        GLES30.glEnable(GLES30.GL_DEPTH_TEST)
        GLES30.glDepthFunc(GLES30.GL_LEQUAL)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        this.width = max(width, 1)
        this.height = max(height, 1)
        GLES30.glViewport(0, 0, this.width, this.height)
    }

    override fun onDrawFrame(gl: GL10?) {
        val snapshot = coordinator.frame()
        val anchor = ToySceneLayout.INITIAL_ANCHOR + snapshot.state.anchorOffset
        val bob = anchor + snapshot.state.position
        updateEffects(snapshot, anchor, bob)
        val progress = transitionProgress()
        val palette = mix(sourceTheme.palette, targetTheme.palette, progress)

        GLES30.glClearColor(palette.skyTop.x, palette.skyTop.y, palette.skyTop.z, 1f)
        GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT or GLES30.GL_DEPTH_BUFFER_BIT)
        drawBackground(snapshot, palette, if (progress < 0.5f) sourceTheme else targetTheme)

        val projection = GlMatrix.perspective(ToySceneLayout.FIELD_OF_VIEW_Y, width.toFloat() / height, 0.1f, 50f)
        val view = GlMatrix.lookAt(ToySceneLayout.CAMERA_EYE, ToySceneLayout.CAMERA_TARGET, Vec3.UP)
        val viewProjection = GlMatrix.multiply(projection, view)
        GLES30.glEnable(GLES30.GL_DEPTH_TEST)
        GLES30.glDepthMask(true)
        GLES30.glEnable(GLES30.GL_CULL_FACE)
        GLES30.glCullFace(GLES30.GL_BACK)
        litProgram.use()
        GLES30.glUniformMatrix4fv(litProgram.uniform("uViewProjection"), 1, false, viewProjection, 0)
        GLES30.glUniform3fv(litProgram.uniform("uCoolLight"), 1, palette.coolLight.toFloatArray(), 0)
        GLES30.glUniform3fv(litProgram.uniform("uWarmLight"), 1, palette.warmLight.toFloatArray(), 0)
        drawToy(snapshot, anchor, bob, palette)
        drawRope(anchor, bob, snapshot.state.ropeLength, palette)
        drawEffects(snapshot.elapsedTime, palette)
    }

    fun setTheme(theme: SeasonTheme, animated: Boolean) {
        if (theme == targetTheme) return
        sourceTheme = targetTheme
        targetTheme = theme
        transitionStarted = System.nanoTime()
        transitionDuration = if (animated) 450_000_000L else 0L
    }

    private fun drawBackground(snapshot: RenderSnapshot, palette: SeasonPalette, theme: SeasonTheme) {
        GLES30.glDisable(GLES30.GL_DEPTH_TEST)
        GLES30.glDepthMask(false)
        backgroundProgram.use()
        GLES30.glBindVertexArray(emptyVao[0])
        GLES30.glUniform2f(backgroundProgram.uniform("uViewport"), width.toFloat(), height.toFloat())
        GLES30.glUniform1f(backgroundProgram.uniform("uTime"), snapshot.elapsedTime)
        GLES30.glUniform1f(backgroundProgram.uniform("uActivity"), snapshot.state.activity)
        GLES30.glUniform1f(backgroundProgram.uniform("uTheme"), theme.shaderIndex)
        uniform3(backgroundProgram, "uSkyTop", palette.skyTop)
        uniform3(backgroundProgram, "uSkyMiddle", palette.skyMiddle)
        uniform3(backgroundProgram, "uSkyBottom", palette.skyBottom)
        uniform3(backgroundProgram, "uAtmosphere", palette.atmosphere)
        uniform3(backgroundProgram, "uAccent", palette.seasonalAccent)
        uniform3(backgroundProgram, "uSilhouette", palette.silhouette)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLES, 0, 3)
        GLES30.glBindVertexArray(0)
    }

    private fun drawToy(snapshot: RenderSnapshot, anchor: Vec3, bob: Vec3, palette: SeasonPalette) {
        val shaftStart = anchor + Vec3(0f, -0.055f, 0f)
        val shaftEnd = shaftStart + Vec3(0f, -1.87f, 0f)
        val shaftDirection = (shaftEnd - shaftStart).normalized(Vec3(0f, -1f, 0f))
        draw(cylinder, GlMatrix.segment(shaftStart, shaftEnd, 0.080f), palette.bamboo, 1f)
        listOf(0.52f, 1.12f).forEach { distance ->
            val center = shaftStart + shaftDirection * distance
            draw(cylinder, GlMatrix.segment(center - shaftDirection * 0.022f, center + shaftDirection * 0.022f, 0.096f), palette.cutBamboo, 2f)
        }
        draw(cylinder, GlMatrix.segment(anchor - shaftDirection * 0.10f, anchor + shaftDirection * 0.14f, 0.118f), palette.cord, 3f)
        drawSphere(anchor - shaftDirection * 0.24f, 0.140f, palette.lacquer, 3f)
        drawSphere(anchor + shaftDirection * 0.17f, 0.086f, palette.cutBamboo, 1f)

        val towardAnchor = (anchor - bob).normalized(Vec3.UP)
        var bodyTangent = stableBodyTangent - towardAnchor * stableBodyTangent.dot(towardAnchor)
        if (bodyTangent.lengthSquared < Vec3.EPSILON) {
            bodyTangent = (if (abs(towardAnchor.y) < 0.9f) Vec3.UP else Vec3(0f, 0f, 1f)).cross(towardAnchor)
        }
        bodyTangent = bodyTangent.normalized(Vec3(0f, 0f, 1f))
        val side = towardAnchor.cross(bodyTangent).normalized(Vec3(1f, 0f, 0f))
        val forward = side.cross(towardAnchor).normalized(Vec3(0f, 0f, 1f))
        val bodyFrame = GlMatrix.multiply(
            GlMatrix.translation(bob),
            GlMatrix.basis(side, towardAnchor, forward),
            GlMatrix.rotation(snapshot.phase * 0.45f * 180f / PI.toFloat(), Vec3.UP),
        )
        draw(bambooTube, GlMatrix.multiply(bodyFrame, GlMatrix.translation(Vec3(0f, -0.52f, 0f)), GlMatrix.scale(Vec3(0.60f, 1.04f, 0.60f))), palette.bamboo, 1f)
        draw(cylinder, GlMatrix.multiply(bodyFrame, GlMatrix.translation(Vec3(0f, -0.085f, 0f)), GlMatrix.scale(Vec3(0.64f, 0.17f, 0.64f))), palette.lacquer, 3f)
        draw(cylinder, GlMatrix.multiply(bodyFrame, GlMatrix.translation(Vec3(0f, 0.006f, 0f)), GlMatrix.scale(Vec3(0.53f, 0.020f, 0.53f))), palette.paleBamboo, 6f)
        draw(torus, GlMatrix.multiply(bodyFrame, GlMatrix.translation(Vec3(0f, 0.010f, 0f)), GlMatrix.rotation(90f, Vec3(1f, 0f, 0f)), GlMatrix.scale(Vec3(0.64f, 0.64f, 0.64f))), palette.lacquer, 3f)
        draw(sphere, GlMatrix.multiply(bodyFrame, GlMatrix.translation(Vec3(0f, 0.024f, 0f)), GlMatrix.scale(Vec3(0.055f, 0.040f, 0.055f))), palette.cord, 4f, snapshot.state.activity * 0.18f)
        floatArrayOf(-1f, 1f).forEachIndexed { index, sign ->
            drawSphereModel(bodyFrame, Vec3(sign * 0.18f, -0.13f, 0.36f), 0.072f, Vec4(0.018f, 0.014f, 0.012f, 1f))
            val flap = wingAngles[index]
            val wingModel = GlMatrix.multiply(
                bodyFrame,
                GlMatrix.translation(Vec3(sign * 0.17f, -0.54f, 0.34f)),
                GlMatrix.rotation(sign * (0.10f + flap * 0.18f) * 180f / PI.toFloat(), Vec3(0f, 0f, 1f)),
                GlMatrix.rotation(sign * 0.055f * 180f / PI.toFloat(), Vec3.UP),
                GlMatrix.rotation(0.045f * 180f / PI.toFloat(), Vec3(1f, 0f, 0f)),
                GlMatrix.scale(Vec3(0.48f, 0.84f, 0.20f)),
            )
            GLES30.glDisable(GLES30.GL_CULL_FACE)
            draw(wing, wingModel, palette.paleBamboo, 5f)
            GLES30.glEnable(GLES30.GL_CULL_FACE)
        }
    }

    private fun drawRope(anchor: Vec3, bob: Vec3, ropeLength: Float, palette: SeasonPalette) {
        val points = WebRopeShape.points(anchor, bob, ropeLength, 25)
        val floats = FloatArray(points.size * 2 * 9)
        var cursor = 0
        points.forEachIndexed { index, point ->
            val previous = points[max(index - 1, 0)]
            val next = points[min(index + 1, points.lastIndex)]
            val tangent = (next - previous).normalized(Vec3.UP)
            val viewDirection = (ToySceneLayout.CAMERA_EYE - point).normalized(Vec3(0f, 0f, 1f))
            var side = tangent.cross(viewDirection).normalized(Vec3(1f, 0f, 0f))
            if (side.lengthSquared < Vec3.EPSILON) side = Vec3(1f, 0f, 0f)
            val normal = side.cross(tangent).normalized(Vec3.UP)
            listOf(point - side * 0.011f, point + side * 0.011f).forEach { vertex ->
                floats[cursor++] = vertex.x; floats[cursor++] = vertex.y; floats[cursor++] = vertex.z
                floats[cursor++] = normal.x; floats[cursor++] = normal.y; floats[cursor++] = normal.z
                floats[cursor++] = index.toFloat() / points.lastIndex; floats[cursor++] = 0f; floats[cursor++] = 0f
            }
        }
        val buffer = ByteBuffer.allocateDirect(floats.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(floats); position(0) }
        GLES30.glBindVertexArray(ropeVao[0])
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, ropeVbo[0])
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, floats.size * 4, buffer, GLES30.GL_STREAM_DRAW)
        GLES30.glDisable(GLES30.GL_CULL_FACE)
        setMaterial(GlMatrix.identity(), palette.rope, 4f, 0f)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, points.size * 2)
        GLES30.glEnable(GLES30.GL_CULL_FACE)
        GLES30.glBindVertexArray(0)
    }

    private fun updateEffects(snapshot: RenderSnapshot, anchor: Vec3, bob: Vec3) {
        val delta = (snapshot.elapsedTime - (lastEffectsTime ?: snapshot.elapsedTime)).coerceIn(0f, 0.05f)
        lastEffectsTime = snapshot.elapsedTime
        val ropeAxis = (anchor - bob).normalized(Vec3.UP)
        val tangentVelocity = snapshot.state.velocity - ropeAxis * snapshot.state.velocity.dot(ropeAxis)
        if (tangentVelocity.length > 0.025f) {
            val measured = tangentVelocity.normalized(stableBodyTangent)
            stableBodyTangent = if (measured.dot(stableBodyTangent) < -0.2f) measured else (stableBodyTangent * 0.82f + measured * 0.18f).normalized(measured)
        }
        for (index in 0..1) {
            val sign = if (index == 0) -1f else 1f
            val target = 0.08f + snapshot.state.activity * sin(snapshot.elapsedTime * 46f + sign * 0.35f) * 0.16f + min(snapshot.state.velocity.length * 0.010f, 0.12f)
            val acceleration = (target - wingAngles[index]) * 82f - wingVelocities[index] * 13f
            wingVelocities[index] += acceleration * delta; wingAngles[index] += wingVelocities[index] * delta
        }
        if (snapshot.state.activity > 0.07f && (trail.firstOrNull()?.distance(bob) ?: Float.MAX_VALUE) > 0.045f) {
            trail.addFirst(bob); while (trail.size > 34) trail.removeLast()
        } else if (snapshot.state.activity < 0.04f && trail.isNotEmpty()) repeat(min(2, trail.size)) { trail.removeLast() }
        if (snapshot.state.activity > 0.16f && snapshot.elapsedTime - lastRippleTime > 0.34f) {
            ripples += Ripple(bob, snapshot.elapsedTime); lastRippleTime = snapshot.elapsedTime
        }
        ripples.removeAll { snapshot.elapsedTime - it.bornAt > 0.9f }
    }

    private fun drawEffects(time: Float, palette: SeasonPalette) {
        trail.forEachIndexed { index, position ->
            if (index % 2 != 0) return@forEachIndexed
            val progress = index.toFloat() / max(trail.size, 1)
            val color = palette.effect.copy(w = (1f - progress) * 0.14f)
            drawSphere(position, 0.064f * (1f - progress) + 0.014f, color, emissive = 0.42f)
        }
        GLES30.glDisable(GLES30.GL_CULL_FACE)
        ripples.forEach { ripple ->
            val progress = ((time - ripple.bornAt) / 0.9f).coerceIn(0f, 1f)
            draw(torus, GlMatrix.multiply(GlMatrix.translation(ripple.position + Vec3(0f, 0f, 0.05f)), GlMatrix.scale(Vec3(0.25f + progress * 0.88f, 0.25f + progress * 0.88f, 0.25f + progress * 0.88f))), palette.effect.copy(w = (1f - progress) * 0.24f), emissive = 0.36f)
        }
        GLES30.glEnable(GLES30.GL_CULL_FACE)
    }

    private fun drawSphere(position: Vec3, scale: Float, color: Vec4, material: Float = 0f, emissive: Float = 0f) =
        draw(sphere, GlMatrix.multiply(GlMatrix.translation(position), GlMatrix.scale(Vec3(scale, scale, scale))), color, material, emissive)

    private fun drawSphereModel(parent: FloatArray, position: Vec3, scale: Float, color: Vec4) =
        draw(sphere, GlMatrix.multiply(parent, GlMatrix.translation(position), GlMatrix.scale(Vec3(scale, scale, scale))), color)

    private fun draw(mesh: GlMesh, model: FloatArray, color: Vec4, material: Float = 0f, emissive: Float = 0f) {
        setMaterial(model, color, material, emissive)
        mesh.draw()
    }

    private fun setMaterial(model: FloatArray, color: Vec4, material: Float, emissive: Float) {
        GLES30.glUniformMatrix4fv(litProgram.uniform("uModel"), 1, false, model, 0)
        GLES30.glUniform4fv(litProgram.uniform("uBaseColor"), 1, color.toFloatArray(), 0)
        GLES30.glUniform2f(litProgram.uniform("uMaterial"), material, emissive)
    }

    private fun uniform3(program: GlProgram, name: String, value: Vec4) =
        GLES30.glUniform3f(program.uniform(name), value.x, value.y, value.z)

    private fun transitionProgress(): Float {
        if (transitionDuration == 0L) return 1f
        val linear = ((System.nanoTime() - transitionStarted).toDouble() / transitionDuration).toFloat().coerceIn(0f, 1f)
        return linear * linear * (3f - 2f * linear)
    }

    private fun mix(first: SeasonPalette, second: SeasonPalette, amount: Float) = SeasonPalette(
        first.skyTop.mix(second.skyTop, amount), first.skyMiddle.mix(second.skyMiddle, amount), first.skyBottom.mix(second.skyBottom, amount),
        first.atmosphere.mix(second.atmosphere, amount), first.seasonalAccent.mix(second.seasonalAccent, amount), first.silhouette.mix(second.silhouette, amount),
        first.bamboo.mix(second.bamboo, amount), first.cutBamboo.mix(second.cutBamboo, amount), first.paleBamboo.mix(second.paleBamboo, amount),
        first.lacquer.mix(second.lacquer, amount), first.cord.mix(second.cord, amount), first.rope.mix(second.rope, amount), first.effect.mix(second.effect, amount),
        first.coolLight.mix(second.coolLight, amount), first.warmLight.mix(second.warmLight, amount),
    )

    private data class Ripple(val position: Vec3, val bornAt: Float)
}
