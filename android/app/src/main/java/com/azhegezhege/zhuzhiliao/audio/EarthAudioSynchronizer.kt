package com.azhegezhege.zhuzhiliao.audio

class EarthAudioSynchronizer(
    private val updateAudio: (revolutionsPerSecond: Float, activity: Float, phase: Float) -> Unit,
) {
    private var isEarthPresented = false

    fun setEarthPresented(isPresented: Boolean) {
        isEarthPresented = isPresented
    }

    fun update(revolutionsPerSecond: Float, activity: Float, phase: Float) {
        if (isEarthPresented) updateAudio(revolutionsPerSecond, activity, phase)
    }
}
