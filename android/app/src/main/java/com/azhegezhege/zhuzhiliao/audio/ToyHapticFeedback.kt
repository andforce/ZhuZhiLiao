package com.azhegezhege.zhuzhiliao.audio

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.azhegezhege.zhuzhiliao.physics.SimulationFrame

class ToyHapticFeedback(context: Context) {
    private val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        context.getSystemService(VibratorManager::class.java).defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }
    private var isSpinning = false

    fun update(frame: SimulationFrame) {
        val shouldBeSpinning = frame.state.activity > 0.1f && frame.state.orbitCoherence >= 0.60f
        if (shouldBeSpinning && !isSpinning) {
            pulse(18, 120)
            isSpinning = true
        } else if (frame.state.activity < 0.035f && frame.revolutionsPerSecond < 0.42f) {
            isSpinning = false
        }
        if (frame.completedWahs > 0) {
            val amplitude = (frame.revolutionsPerSecond / 3.2f * 255f).toInt().coerceIn(148, 255)
            pulse(12, amplitude)
        }
    }

    fun reset() { isSpinning = false }

    private fun pulse(milliseconds: Long, amplitude: Int) {
        if (vibrator.hasVibrator()) vibrator.vibrate(VibrationEffect.createOneShot(milliseconds, amplitude))
    }
}
