package com.azhegezhege.zhuzhiliao.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.SoundPool
import com.azhegezhege.zhuzhiliao.R
import kotlin.math.pow
import kotlin.math.sin

class ToyAudioEngine(context: Context) {
    private data class EarthVoice(
        val descriptor: EarthAudioVoiceDescriptor,
        val player: MediaPlayer,
    )

    private val applicationContext = context.applicationContext
    private val audioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_GAME)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()
    private val soundPool = SoundPool.Builder()
        .setMaxStreams(1)
        .setAudioAttributes(audioAttributes)
        .build()
    private val earthVoices = linkedMapOf<String, EarthVoice>()
    private var soundID = 0
    private var streamID = 0
    private var isLoaded = false
    private var wantsPlayback = false
    private var isPaused = false
    private var isEarthPresented = false
    private var isEarthMuted = false
    private var mainVolume = 0f

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
        earthVoices.values.forEach { voice ->
            runCatching {
                if (!voice.player.isPlaying) voice.player.start()
            }
        }
    }

    fun pause() {
        wantsPlayback = false
        if (streamID != 0 && !isPaused) {
            soundPool.pause(streamID)
            isPaused = true
        }
        earthVoices.values.forEach { voice ->
            runCatching {
                if (voice.player.isPlaying) voice.player.pause()
            }
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
        mainVolume = 0.85f * activity.coerceIn(0f, 1f).pow(1.3f)
        if (streamID != 0) {
            soundPool.setRate(streamID, rate)
            val volume = if (isEarthPresented) 0f else mainVolume
            soundPool.setVolume(streamID, volume, volume)
        }
    }

    fun setEarthPresented(isPresented: Boolean) {
        if (isEarthPresented == isPresented) return
        isEarthPresented = isPresented
        if (streamID != 0) {
            val volume = if (isPresented) 0f else mainVolume
            soundPool.setVolume(streamID, volume, volume)
        }
        if (!isPresented) reconcileEarthVoices(emptyList())
    }

    fun updateEarthVoices(descriptors: List<EarthAudioVoiceDescriptor>) {
        if (!isEarthPresented) return
        reconcileEarthVoices(descriptors)
    }

    fun setEarthMuted(isMuted: Boolean) {
        if (isEarthMuted == isMuted) return
        isEarthMuted = isMuted
        updateEarthVoiceVolumes()
    }

    fun release() {
        wantsPlayback = false
        earthVoices.values.forEach { releaseEarthVoice(it) }
        earthVoices.clear()
        soundPool.release()
    }

    private fun reconcileEarthVoices(descriptors: List<EarthAudioVoiceDescriptor>) {
        val requested = descriptors.associateBy(EarthAudioVoiceDescriptor::id)
        earthVoices.keys.toList().forEach { id ->
            if (id !in requested) {
                earthVoices.remove(id)?.let(::releaseEarthVoice)
            }
        }

        descriptors.forEach { descriptor ->
            if (descriptor.id in earthVoices) return@forEach
            createEarthPlayer(descriptor)?.let { player ->
                earthVoices[descriptor.id] = EarthVoice(descriptor, player)
                if (wantsPlayback) runCatching { player.start() }
            }
        }
        updateEarthVoiceVolumes()
    }

    private fun createEarthPlayer(descriptor: EarthAudioVoiceDescriptor): MediaPlayer? {
        val asset = applicationContext.resources.openRawResourceFd(R.raw.zhuzhiliao_loop)
            ?: return null
        val player = MediaPlayer()
        return try {
            player.setAudioAttributes(audioAttributes)
            player.setDataSource(asset.fileDescriptor, asset.startOffset, asset.length)
            player.isLooping = true
            player.prepare()
            player.setVolume(0f, 0f)
            if (player.duration > 1) {
                val position = (player.duration * descriptor.normalizedStartPhase)
                    .toInt()
                    .coerceIn(0, player.duration - 1)
                player.seekTo(position.toLong(), MediaPlayer.SEEK_CLOSEST)
            }
            player
        } catch (_: Throwable) {
            player.release()
            null
        } finally {
            asset.close()
        }
    }

    private fun updateEarthVoiceVolumes() {
        val gain = EarthAudioVoicePlanner.normalizedGain(
            voiceCount = earthVoices.size,
            isMuted = isEarthMuted,
        )
        earthVoices.values.forEach { voice ->
            runCatching { voice.player.setVolume(gain, gain) }
        }
    }

    private fun releaseEarthVoice(voice: EarthVoice) {
        runCatching { voice.player.setVolume(0f, 0f) }
        runCatching { voice.player.stop() }
        runCatching { voice.player.release() }
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
