package com.azhegezhege.zhuzhiliao.physics

import com.azhegezhege.zhuzhiliao.math.Vec3
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.math.PI

class OrbitCounterTest {
    @Test
    fun `continuous qualified orbit completes one wah`() {
        val counter = OrbitCounter()
        var completed = 0
        repeat(4) { completed += counter.update((PI / 2).toFloat(), Vec3(0f, 0f, 1f), true) }
        assertEquals(1, completed)
    }

    @Test
    fun `direction reversal breaks orbit continuity`() {
        val counter = OrbitCounter()
        var completed = 0
        repeat(2) { completed += counter.update((PI / 2).toFloat(), Vec3(0f, 0f, 1f), true) }
        repeat(2) { completed += counter.update((PI / 2).toFloat(), Vec3(0f, 0f, -1f), true) }
        assertEquals(0, completed)
    }

    @Test
    fun `unqualified jitter resets partial orbit`() {
        val counter = OrbitCounter()
        counter.update(PI.toFloat(), Vec3(0f, 0f, 1f), true)
        counter.update(0f, Vec3(0f, 0f, 1f), false)
        assertEquals(0, counter.update(PI.toFloat(), Vec3(0f, 0f, 1f), true))
    }
}
