package com.azhegezhege.zhuzhiliao.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import com.azhegezhege.zhuzhiliao.R
import kotlin.math.pow
import kotlin.math.sin

class ToyAudioEngine(context: Context) {
    private val soundPool = SoundPool.Builder()
        .setMaxStreams(1)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build(),
        )
        .build()
    private var soundID = 0
    private var streamID = 0
    private var isLoaded = false
    private var wantsPlayback = false
    private var isPaused = false

    init {
        soundPool.setOnLoadCompleteListener { _, loadedSoundID, status ->
            if (status == 0 && (soundID == 0 || loadedSoundID == soundID)) {
                soundID = loadedSoundID
                isLoaded = true
                if (wantsPlayback) ensurePlaying()
            }
        }
        soundID = soundPool.load(context, R.raw.zhuzhiliao_loop, 1)
    }

    fun start() {
        wantsPlayback = true
        if (isLoaded) ensurePlaying()
    }

    fun pause() {
        wantsPlayback = false
        if (streamID != 0 && !isPaused) {
            soundPool.pause(streamID)
            isPaused = true
        }
    }

    fun update(revolutionsPerSecond: Float, activity: Float, phase: Float) {
        if (!isLoaded) return
        ensurePlaying()
        val normalizedSpeed = (revolutionsPerSecond / 2.33f).coerceAtLeast(0.0001f)
        val baseRate = normalizedSpeed.pow(0.7f).coerceIn(0.6f, 1.5f)
        val detuneCents = 50f * sin(phase + 0.9f) * (activity * 1.6f).coerceIn(0f, 1f)
        val phaseRate = 2f.pow(detuneCents / 1_200f)
        val rate = (baseRate * phaseRate).coerceIn(0.6f, 1.5f)
        val volume = 0.85f * activity.coerceIn(0f, 1f).pow(1.3f)
        if (streamID != 0) {
            soundPool.setRate(streamID, rate)
            soundPool.setVolume(streamID, volume, volume)
        }
    }

    fun release() {
        wantsPlayback = false
        soundPool.release()
    }

    private fun ensurePlaying() {
        if (!wantsPlayback || !isLoaded) return
        if (streamID == 0) {
            streamID = soundPool.play(soundID, 0f, 0f, 1, -1, 1f)
            isPaused = false
        } else if (isPaused) {
            soundPool.resume(streamID)
            isPaused = false
        }
    }
}
