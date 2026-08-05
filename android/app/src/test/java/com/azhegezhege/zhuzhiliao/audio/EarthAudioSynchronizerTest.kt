package com.azhegezhege.zhuzhiliao.audio

import org.junit.Assert.assertEquals
import org.junit.Test

class EarthAudioSynchronizerTest {
    @Test
    fun `earth presentation keeps wah audio synchronized with the simulation`() {
        val updates = mutableListOf<AudioUpdate>()
        val synchronizer = EarthAudioSynchronizer { speed, activity, phase ->
            updates += AudioUpdate(speed, activity, phase)
        }

        synchronizer.setEarthPresented(true)
        synchronizer.update(3.1f, 0.72f, 1.4f)

        assertEquals(listOf(AudioUpdate(3.1f, 0.72f, 1.4f)), updates)
    }

    @Test
    fun `leaving earth returns audio updates to the toy renderer`() {
        var updateCount = 0
        val synchronizer = EarthAudioSynchronizer { _, _, _ -> updateCount += 1 }

        synchronizer.setEarthPresented(true)
        synchronizer.update(1f, 0.5f, 0f)
        synchronizer.setEarthPresented(false)
        synchronizer.update(2f, 0.8f, 1f)

        assertEquals(1, updateCount)
    }

    private data class AudioUpdate(val speed: Float, val activity: Float, val phase: Float)
}
