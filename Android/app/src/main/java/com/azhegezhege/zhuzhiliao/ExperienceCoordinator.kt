package com.azhegezhege.zhuzhiliao

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.azhegezhege.zhuzhiliao.audio.EarthAudioVoicePlanner
import com.azhegezhege.zhuzhiliao.audio.ToyAudioEngine
import com.azhegezhege.zhuzhiliao.audio.ToyHapticFeedback
import com.azhegezhege.zhuzhiliao.math.Vec3
import com.azhegezhege.zhuzhiliao.motion.MotionController
import com.azhegezhege.zhuzhiliao.motion.ShakeDrive
import com.azhegezhege.zhuzhiliao.network.CounterService
import com.azhegezhege.zhuzhiliao.network.CounterStats
import com.azhegezhege.zhuzhiliao.network.EarthBounds
import com.azhegezhege.zhuzhiliao.network.EarthNode
import com.azhegezhege.zhuzhiliao.network.EarthSnapshot
import com.azhegezhege.zhuzhiliao.network.LeaderboardSnapshot
import com.azhegezhege.zhuzhiliao.physics.MotionInput
import com.azhegezhege.zhuzhiliao.physics.SimulationFrame
import com.azhegezhege.zhuzhiliao.physics.ToyPhysicsState
import com.azhegezhege.zhuzhiliao.physics.ToySimulation
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

enum class ToyInteractionState(val title: String, val detail: String) {
    IDLE("轻轻往复摇动手机", "任意方向短幅连续摇动 · 也可按住屏幕滑动"),
    SHAKING("已感应，继续摇动", "正在蓄力成圈 · 不需要大幅甩动"),
    SPINNING("竹知了已经转起来了", "持续摇动会转得更快、叫得更响"),
    TOUCHING("正在用手指控制", "沿屏幕连续画圈 · 松手后恢复动作控制"),
    AUTOMATIC("正在自动演示", "触摸屏幕后可切换为手指控制"),
    UNAVAILABLE("按住屏幕滑动", "动作传感器不可用 · 请沿屏幕连续画圈"),
}

data class ExperienceUiState(
    val revolutionsPerSecond: Float = 0f,
    val activity: Float = 0f,
    val stats: CounterStats = CounterStats(0, 0),
    val personalWahs: Int = 0,
    val motionIsAvailable: Boolean = false,
    val interactionState: ToyInteractionState = ToyInteractionState.IDLE,
    val leaderboardCode: String? = null,
    val earthIsEnabled: Boolean = false,
    val earthCellID: String? = null,
)

data class RenderSnapshot(
    val state: ToyPhysicsState,
    val revolutionsPerSecond: Float,
    val phase: Float,
    val elapsedTime: Float,
    val rotationRate: Vec3,
    val emittedWahs: Int,
)

object ToySceneLayout {
    val CAMERA_EYE = Vec3(0f, 0.10f, 16f)
    val CAMERA_TARGET = Vec3(0f, -0.15f, 0f)
    val FIELD_OF_VIEW_Y = (42.0 * PI / 180.0).toFloat()
    const val VISIBLE_HEIGHT_AT_TOY_PLANE = 12.28f
    val INITIAL_ANCHOR = Vec3(0.24f, 0.72f, 0f)
}

class ExperienceCoordinator(context: Context) {
    private val motionController = MotionController(context)
    private val audioEngine = ToyAudioEngine(context)
    private val counterService = CounterService(context)
    private val hapticFeedback = ToyHapticFeedback(context)
    private val simulation = ToySimulation()
    private val handler = Handler(Looper.getMainLooper())
    private val frameLock = Any()
    private var latestSimulationFrame = simulation.advance(MotionInput.ZERO, 0.0)
    private var latestRotationRate = Vec3.ZERO
    private var pendingRenderedWahs = 0
    private var awaitingCalibratedGravity = true
    private var elapsedTime = 0f
    private var automaticPhase = 0f
    private var automaticRps = 0f
    private var pointerAnchorTarget: Vec3? = null
    private var pointerIsActive = false
    private var hasUsedPointerFallback = false
    private var latestShakeDrive = ShakeDrive.INACTIVE
    private var automaticMode = false
    private var isRunning = false
    private var previousTimeNanos = 0L
    private var lastHudTime = 0L
    var lastLocalWahMillis: Long? = null; private set
    var earthRevision = 0; private set
    var uiState = ExperienceUiState(); private set
    var stateListener: ((ExperienceUiState) -> Unit)? = null
    var earthRevisionListener: ((Int) -> Unit)? = null
    var localWahListener: (() -> Unit)? = null

    init {
        counterService.stateListener = { handler.post(::publishState) }
        counterService.earthRevisionListener = { revision ->
            handler.post {
                earthRevision = revision
                earthRevisionListener?.invoke(revision)
            }
        }
    }

    fun start() {
        if (isRunning) return
        isRunning = true
        motionController.start()
        automaticMode = !motionController.isAvailable && !hasUsedPointerFallback
        previousTimeNanos = System.nanoTime()
        handler.post(simulationLoop)
        audioEngine.start()
        counterService.start()
        publishState()
    }

    fun pause() {
        if (!isRunning) return
        isRunning = false
        handler.removeCallbacks(simulationLoop)
        motionController.stop()
        audioEngine.pause()
        hapticFeedback.reset()
        counterService.stop()
    }

    fun release() {
        pause()
        audioEngine.release()
        counterService.release()
    }

    fun recalibrate() {
        pointerAnchorTarget = Vec3.ZERO
        pointerIsActive = false
        latestShakeDrive = ShakeDrive.INACTIVE
        motionController.resetCalibration()
        if (automaticMode || !motionController.isAvailable) {
            resetSimulation(Vec3(0f, -1f, 0f))
            awaitingCalibratedGravity = false
        } else awaitingCalibratedGravity = true
        publishState()
    }

    fun movePointer(x: Float, y: Float, viewportWidth: Float, viewportHeight: Float) {
        if (viewportWidth <= 0f || viewportHeight <= 0f) return
        if (!pointerIsActive) {
            motionController.resetGestureState(preservingDirection = true)
            latestShakeDrive = ShakeDrive.INACTIVE
        }
        val visibleWidth = ToySceneLayout.VISIBLE_HEIGHT_AT_TOY_PLANE * viewportWidth / viewportHeight
        val normalizedX = x / viewportWidth - 0.5f
        val normalizedY = 0.5f - y / viewportHeight
        val worldPoint = Vec3(
            normalizedX * visibleWidth,
            ToySceneLayout.CAMERA_TARGET.y + normalizedY * ToySceneLayout.VISIBLE_HEIGHT_AT_TOY_PLANE,
            0f,
        )
        pointerAnchorTarget = worldPoint - ToySceneLayout.INITIAL_ANCHOR
        pointerIsActive = true
        hasUsedPointerFallback = true
        automaticMode = false
        publishState()
    }

    fun endPointerInteraction() {
        pointerIsActive = false
        pointerAnchorTarget = Vec3.ZERO
        latestShakeDrive = ShakeDrive.INACTIVE
        motionController.resetGestureState(preservingDirection = true)
        publishState()
    }

    fun frame(): RenderSnapshot = synchronized(frameLock) {
        val frame = latestSimulationFrame
        val emitted = pendingRenderedWahs
        pendingRenderedWahs = 0
        audioEngine.update(frame.revolutionsPerSecond, frame.state.activity, frame.phase)
        RenderSnapshot(
            state = frame.state.copy(),
            revolutionsPerSecond = frame.revolutionsPerSecond,
            phase = frame.phase,
            elapsedTime = elapsedTime,
            rotationRate = latestRotationRate,
            emittedWahs = emitted,
        )
    }

    suspend fun loadLeaderboard(): LeaderboardSnapshot = counterService.loadLeaderboard()
    suspend fun resetAnonymousIdentity() {
        counterService.resetAnonymousIdentity()
        publishState()
    }

    suspend fun setEarthLocation(cellID: String) {
        counterService.setEarthLocation(cellID)
        publishState()
    }

    suspend fun disableEarth() {
        counterService.disableEarth()
        publishState()
    }
    suspend fun loadEarthSnapshot(detail: Int, bounds: List<EarthBounds> = emptyList()): EarthSnapshot =
        counterService.loadEarthSnapshot(detail, bounds)

    fun setEarthPresented(isPresented: Boolean) {
        audioEngine.setEarthPresented(isPresented)
    }

    fun setEarthAudioMuted(isMuted: Boolean) {
        audioEngine.setEarthMuted(isMuted)
    }

    fun synchronizeEarthAudio(
        nodes: List<EarthNode>,
        serverClockOffsetMilliseconds: Long,
        nowMilliseconds: Long = System.currentTimeMillis(),
    ): Long? {
        val serverNow = nowMilliseconds + serverClockOffsetMilliseconds
        val voices = EarthAudioVoicePlanner.voices(
            nodes = nodes,
            serverNow = serverNow,
            serverClockOffsetMilliseconds = serverClockOffsetMilliseconds,
            localWahAt = lastLocalWahMillis,
        )
        audioEngine.updateEarthVoices(voices)
        return voices.minOfOrNull { it.activeUntil }?.minus(serverClockOffsetMilliseconds)
    }

    private val simulationLoop = object : Runnable {
        override fun run() {
            if (!isRunning) return
            val now = System.nanoTime()
            stepSimulation(((now - previousTimeNanos) / 1_000_000_000.0).coerceIn(0.0, 0.05))
            previousTimeNanos = now
            if (now - lastHudTime >= 120_000_000L) {
                lastHudTime = now
                publishState()
            }
            handler.postDelayed(this, 8L)
        }
    }

    private fun stepSimulation(deltaTime: Double) {
        val input = when {
            pointerIsActive && pointerAnchorTarget != null -> {
                latestRotationRate = Vec3.ZERO
                latestShakeDrive = ShakeDrive.INACTIVE
                MotionInput(Vec3.ZERO, Vec3(0f, -1f, 0f), Vec3.ZERO, pointerAnchorTarget)
            }
            automaticMode -> {
                val delta = deltaTime.toFloat()
                automaticRps += (3.4f - automaticRps) * minOf(1f, delta * 1.1f)
                automaticPhase += automaticRps * delta * ToySimulation.FULL_TURN
                val radius = simulation.state.ropeLength * 13f / 28f
                val target = Vec3(cos(automaticPhase) * radius, sin(automaticPhase) * radius, 0f)
                latestRotationRate = Vec3.ZERO
                MotionInput(Vec3.ZERO, Vec3(0f, -1f, 0f), Vec3.ZERO, target)
            }
            else -> {
                val sample = motionController.latestSample()
                if (sample.isAvailable && awaitingCalibratedGravity) {
                    resetSimulation(sample.gravityDirection)
                    awaitingCalibratedGravity = false
                }
                latestRotationRate = if (sample.isAvailable) sample.rotationRate else Vec3.ZERO
                latestShakeDrive = if (sample.isAvailable) sample.shakeDrive else ShakeDrive.INACTIVE
                MotionInput(
                    if (sample.isAvailable) sample.userAcceleration else Vec3.ZERO,
                    if (sample.isAvailable) sample.gravityDirection else Vec3(0f, -1f, 0f),
                    latestRotationRate,
                    Vec3.ZERO,
                    latestShakeDrive,
                )
            }
        }
        val frame = simulation.advance(input, deltaTime)
        elapsedTime += deltaTime.toFloat()
        synchronized(frameLock) {
            latestSimulationFrame = frame
            pendingRenderedWahs += frame.completedWahs
        }
        if (!automaticMode) {
            hapticFeedback.update(frame)
            if (frame.completedWahs > 0) {
                counterService.record(frame.completedWahs)
                lastLocalWahMillis = System.currentTimeMillis()
                localWahListener?.invoke()
            }
        }
    }

    private fun publishState() {
        val frame = synchronized(frameLock) { latestSimulationFrame }
        uiState = ExperienceUiState(
            revolutionsPerSecond = frame.revolutionsPerSecond,
            activity = frame.state.activity,
            stats = counterService.stats,
            personalWahs = counterService.personalWahs,
            motionIsAvailable = motionController.isAvailable,
            interactionState = resolvedInteractionState(frame),
            leaderboardCode = counterService.publicCode,
            earthIsEnabled = counterService.earthIsEnabled,
            earthCellID = counterService.earthCellID,
        )
        stateListener?.invoke(uiState)
    }

    private fun resolvedInteractionState(frame: SimulationFrame): ToyInteractionState = when {
        pointerIsActive -> ToyInteractionState.TOUCHING
        automaticMode -> ToyInteractionState.AUTOMATIC
        !motionController.isAvailable -> ToyInteractionState.UNAVAILABLE
        frame.state.activity > 0.08f && frame.state.orbitCoherence >= 0.60f -> ToyInteractionState.SPINNING
        latestShakeDrive.isActive -> ToyInteractionState.SHAKING
        else -> ToyInteractionState.IDLE
    }

    private fun resetSimulation(gravityDirection: Vec3) {
        simulation.reset(gravityDirection)
        synchronized(frameLock) {
            latestSimulationFrame = simulation.advance(MotionInput.ZERO, 0.0)
            pendingRenderedWahs = 0
        }
        latestRotationRate = Vec3.ZERO
        automaticRps = 0f
        hapticFeedback.reset()
    }
}
