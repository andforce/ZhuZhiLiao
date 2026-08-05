package com.azhegezhege.zhuzhiliao.motion

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import com.azhegezhege.zhuzhiliao.math.Quaternion
import com.azhegezhege.zhuzhiliao.math.Vec3

data class MotionSample(
    val userAcceleration: Vec3,
    val gravityDirection: Vec3,
    val rotationRate: Vec3,
    val relativeAttitude: Quaternion,
    val shakeDrive: ShakeDrive,
    val timestamp: Double,
    val isAvailable: Boolean,
) {
    companion object {
        val UNAVAILABLE = MotionSample(
            Vec3.ZERO,
            Vec3(0f, -1f, 0f),
            Vec3.ZERO,
            Quaternion.IDENTITY,
            ShakeDrive.INACTIVE,
            0.0,
            false,
        )
    }
}

class MotionController(context: Context) : SensorEventListener {
    private val manager = context.getSystemService(SensorManager::class.java)
    private val rotationSensor = manager.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
        ?: manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private val accelerationSensor = manager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
    private val gravitySensor = manager.getDefaultSensor(Sensor.TYPE_GRAVITY)
    private val rawAccelerationSensor = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        ?.takeIf { accelerationSensor == null || gravitySensor == null }
    private val gyroscopeSensor = manager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
    private val sensorThread = HandlerThread("ZhuZhiLiao.Motion")
    private val lock = Any()
    private val accelerationFilter = MotionSampleFilter()
    private val shakeDetector = ShakeGestureDetector()
    private var referenceAttitude: Quaternion? = null
    private var currentAttitude = Quaternion.IDENTITY
    private var currentAcceleration = Vec3.ZERO
    private var currentGravity = MotionCoordinateMapper.DEFAULT_SENSOR_GRAVITY
    private var currentRotationRate = Vec3.ZERO
    private var rawGravityMetersPerSecondSquared = Vec3.ZERO
    private var hasRawGravity = false
    private var sample = MotionSample.UNAVAILABLE
    private var started = false

    val isAvailable: Boolean
        get() = accelerationSensor != null || rawAccelerationSensor != null

    fun start() {
        if (started || !isAvailable) return
        started = true
        if (!sensorThread.isAlive) sensorThread.start()
        val handler = Handler(sensorThread.looper)
        listOfNotNull(rotationSensor, accelerationSensor, gravitySensor, rawAccelerationSensor, gyroscopeSensor)
            .distinctBy(Sensor::getType)
            .forEach { sensor ->
            manager.registerListener(this, sensor, 10_000, handler)
        }
        resetCalibration()
    }

    fun stop() {
        if (!started) return
        started = false
        manager.unregisterListener(this)
        synchronized(lock) {
            resetLocked()
            sample = MotionSample.UNAVAILABLE
        }
    }

    fun resetCalibration() = synchronized(lock) { resetLocked() }

    fun resetGestureState(preservingDirection: Boolean = true) = synchronized(lock) {
        sample = sample.copy(shakeDrive = shakeDetector.reset(preservingDirection))
    }

    fun latestSample(): MotionSample = synchronized(lock) {
        val age = SystemClock.elapsedRealtimeNanos() / 1_000_000_000.0 - sample.timestamp
        if (!sample.isAvailable || age <= 0.15) return@synchronized sample
        sample.copy(
            userAcceleration = Vec3.ZERO,
            rotationRate = Vec3.ZERO,
            shakeDrive = ShakeDrive.inactive(sample.shakeDrive.orbitAxis),
        )
    }

    override fun onSensorChanged(event: SensorEvent) = synchronized(lock) {
        if (!started) return@synchronized
        val raw = Vec3(event.values[0], event.values[1], event.values[2])
        var hasFreshAcceleration = false
        when (event.sensor.type) {
            Sensor.TYPE_GAME_ROTATION_VECTOR, Sensor.TYPE_ROTATION_VECTOR -> {
                val quaternion = FloatArray(4)
                SensorManager.getQuaternionFromVector(quaternion, event.values)
                currentAttitude = Quaternion(quaternion[1], quaternion[2], quaternion[3], quaternion[0]).normalized()
                if (referenceAttitude == null) referenceAttitude = currentAttitude
            }
            Sensor.TYPE_LINEAR_ACCELERATION -> {
                currentAcceleration = raw / STANDARD_GRAVITY
                hasFreshAcceleration = true
            }
            Sensor.TYPE_GRAVITY -> currentGravity = raw / STANDARD_GRAVITY
            Sensor.TYPE_ACCELEROMETER -> {
                rawGravityMetersPerSecondSquared = if (hasRawGravity) {
                    rawGravityMetersPerSecondSquared * 0.90f + raw * 0.10f
                } else raw
                hasRawGravity = true
                if (gravitySensor == null) currentGravity = rawGravityMetersPerSecondSquared / STANDARD_GRAVITY
                if (accelerationSensor == null) currentAcceleration = (raw - rawGravityMetersPerSecondSquared) / STANDARD_GRAVITY
                hasFreshAcceleration = accelerationSensor == null
            }
            Sensor.TYPE_GYROSCOPE -> currentRotationRate = raw
        }
        if (!hasFreshAcceleration) return@synchronized
        val reference = referenceAttitude ?: Quaternion.IDENTITY
        val deviceToCalibratedScene = (reference * currentAttitude.conjugate()).normalized()
        val measuredAcceleration = deviceToCalibratedScene.act(currentAcceleration)
        val gravity = MotionCoordinateMapper.sceneGravity(currentGravity, deviceToCalibratedScene)
        val rotationRate = deviceToCalibratedScene.act(currentRotationRate)
        val timestamp = event.timestamp / 1_000_000_000.0
        sample = MotionSample(
            userAcceleration = accelerationFilter.process(measuredAcceleration, timestamp),
            gravityDirection = gravity,
            rotationRate = rotationRate,
            relativeAttitude = deviceToCalibratedScene,
            shakeDrive = shakeDetector.process(measuredAcceleration, rotationRate, timestamp),
            timestamp = timestamp,
            isAvailable = true,
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun resetLocked() {
        referenceAttitude = null
        currentAttitude = Quaternion.IDENTITY
        currentAcceleration = Vec3.ZERO
        currentGravity = MotionCoordinateMapper.DEFAULT_SENSOR_GRAVITY
        currentRotationRate = Vec3.ZERO
        rawGravityMetersPerSecondSquared = Vec3.ZERO
        hasRawGravity = false
        accelerationFilter.reset()
        shakeDetector.reset()
        sample = MotionSample.UNAVAILABLE
    }

    companion object { private const val STANDARD_GRAVITY = 9.80665f }
}
