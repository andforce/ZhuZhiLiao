package com.azhegezhege.zhuzhiliao.audio

import com.azhegezhege.zhuzhiliao.earth.EarthActivityWindow
import com.azhegezhege.zhuzhiliao.network.EarthNode
import kotlin.math.max
import kotlin.math.sqrt

data class EarthAudioVoiceDescriptor(
    val id: String,
    val activeUntil: Long,
    val normalizedStartPhase: Double,
)

object EarthAudioVoicePlanner {
    fun voices(
        nodes: List<EarthNode>,
        serverNow: Long,
        serverClockOffsetMilliseconds: Long,
        localWahAt: Long?,
    ): List<EarthAudioVoiceDescriptor> {
        val localActiveUntil = localWahAt?.let {
            EarthActivityWindow.activeUntil(it) + serverClockOffsetMilliseconds
        }
        val result = mutableListOf<EarthAudioVoiceDescriptor>()

        nodes.forEach { node ->
            val localDeadline = localActiveUntil.takeIf { node.highlightsMe }
            val activeUntil = max(node.activeUntil ?: 0L, localDeadline ?: 0L)
            if (activeUntil <= serverNow) return@forEach

            val voiceCount = when (node.kind) {
                EarthNode.Kind.PLAYER -> 1
                EarthNode.Kind.CLUSTER -> max(
                    node.activeCount ?: 0,
                    if (localDeadline == null) 0 else 1,
                )
            }
            repeat(voiceCount) { index ->
                val id = "${node.kind.name.lowercase()}:${node.id}:$index"
                result += EarthAudioVoiceDescriptor(
                    id = id,
                    activeUntil = activeUntil,
                    normalizedStartPhase = normalizedPhase(id),
                )
            }
        }

        return result.sortedBy(EarthAudioVoiceDescriptor::id)
    }

    fun normalizedGain(voiceCount: Int, isMuted: Boolean = false): Float {
        if (voiceCount <= 0 || isMuted) return 0f
        return 0.8f / sqrt(voiceCount.toFloat())
    }

    private fun normalizedPhase(value: String): Double {
        var hash = 14_695_981_039_346_656_037UL
        value.encodeToByteArray().forEach { byte ->
            hash = hash xor byte.toUByte().toULong()
            hash *= 1_099_511_628_211UL
        }
        return (hash % 10_000UL).toDouble() / 10_000.0
    }
}
