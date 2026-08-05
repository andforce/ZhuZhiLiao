package com.azhegezhege.zhuzhiliao.motion

import com.azhegezhege.zhuzhiliao.math.Vec3
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

class MotionSampleFilterTest {
    @Test
    fun deadZoneAndMaximumMagnitudeProtectTheSimulation() {
        val filter = MotionSampleFilter(
            MotionFilterConfiguration(deadZone = 0.03f, maximumMagnitude = 2.5f, smoothingFactor = 1f),
        )

        assertEquals(Vec3.ZERO, filter.process(Vec3(0.01f, -0.01f, 0f), 1.0))
        val clamped = filter.process(Vec3(6f, 8f, 0f), 2.0)
        assertEquals(2.5f, clamped.length, 0.0001f)
        assertTrue(clamped.x > 0f && clamped.y > 0f)
    }

    @Test
    fun repeatedShortShakesAlongEveryAxisActivateDrive() {
        listOf(Vec3(1f, 0f, 0f), Vec3(0f, 1f, 0f), Vec3(0f, 0f, 1f)).forEach { axis ->
            val detector = ShakeGestureDetector()
            var drive = ShakeDrive.INACTIVE
            var maximumIntensity = 0f
            repeat(81) { index ->
                val time = index * 0.01
                val phase = (time * 3.0 * 2.0 * PI).toFloat()
                drive = detector.process(axis * (sin(phase) * 0.45f), Vec3.ZERO, time)
                maximumIntensity = maxOf(maximumIntensity, drive.intensity)
            }
            assertTrue("axis=$axis", drive.isActive)
            assertTrue("axis=$axis", maximumIntensity > 0.05f)
            assertEquals(-1f, drive.orbitAxis.z, 0.0001f)
        }
    }
}
