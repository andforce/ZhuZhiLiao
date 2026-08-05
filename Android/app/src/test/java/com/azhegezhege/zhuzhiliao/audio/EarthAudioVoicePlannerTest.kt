package com.azhegezhege.zhuzhiliao.audio

import com.azhegezhege.zhuzhiliao.network.EarthNode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class EarthAudioVoicePlannerTest {
    @Test
    fun `creates one voice per player and active cluster member`() {
        val voices = EarthAudioVoicePlanner.voices(
            nodes = listOf(
                node("player", EarthNode.Kind.PLAYER, activeUntil = 1_120_000L),
                node(
                    "cluster",
                    EarthNode.Kind.CLUSTER,
                    activeCount = 3,
                    activeUntil = 1_110_000L,
                ),
            ),
            serverNow = 1_000_000L,
            serverClockOffsetMilliseconds = 0L,
            localWahAt = null,
        )

        assertEquals(4, voices.size)
        assertEquals(4, voices.map { it.id }.toSet().size)
        assertEquals(3, voices.count { it.id.startsWith("cluster:") })
    }

    @Test
    fun `omits expired nodes using server time`() {
        val voices = EarthAudioVoicePlanner.voices(
            nodes = listOf(
                node("expired", EarthNode.Kind.PLAYER, activeUntil = 999_999L),
                node("active", EarthNode.Kind.PLAYER, activeUntil = 1_000_001L),
            ),
            serverNow = 1_000_000L,
            serverClockOffsetMilliseconds = 12_000L,
            localWahAt = null,
        )

        assertEquals(listOf("player:active:0"), voices.map { it.id })
        assertEquals(1_000_001L, voices.single().activeUntil)
    }

    @Test
    fun `uses a local wah to activate my stale cluster`() {
        val voices = EarthAudioVoicePlanner.voices(
            nodes = listOf(
                node(
                    "mine",
                    EarthNode.Kind.CLUSTER,
                    activeCount = 0,
                    activeUntil = null,
                    containsMe = true,
                ),
            ),
            serverNow = 1_050_500L,
            serverClockOffsetMilliseconds = 500L,
            localWahAt = 1_000_000L,
        )

        assertEquals(1, voices.size)
        assertEquals(1_600_500L, voices.single().activeUntil)
    }

    @Test
    fun `voice identity phase and gain are stable`() {
        val cluster = node(
            "stable",
            EarthNode.Kind.CLUSTER,
            activeCount = 2,
            activeUntil = 1_120_000L,
        )
        val first = EarthAudioVoicePlanner.voices(
            listOf(cluster),
            serverNow = 1_000_000L,
            serverClockOffsetMilliseconds = 0L,
            localWahAt = null,
        )
        val second = EarthAudioVoicePlanner.voices(
            listOf(cluster),
            serverNow = 1_000_100L,
            serverClockOffsetMilliseconds = 0L,
            localWahAt = null,
        )

        assertEquals(first, second)
        assertNotEquals(first[0].normalizedStartPhase, first[1].normalizedStartPhase)
        assertEquals(0f, EarthAudioVoicePlanner.normalizedGain(0), 0.0001f)
        assertEquals(
            0f,
            EarthAudioVoicePlanner.normalizedGain(4, isMuted = true),
            0.0001f,
        )
        assertEquals(0.4f, EarthAudioVoicePlanner.normalizedGain(4), 0.0001f)
    }

    private fun node(
        id: String,
        kind: EarthNode.Kind,
        activeCount: Int? = null,
        activeUntil: Long?,
        isMe: Boolean = false,
        containsMe: Boolean = false,
    ) = EarthNode(
        kind = kind,
        id = id,
        code = id.takeIf { kind == EarthNode.Kind.PLAYER },
        score = 1.takeIf { kind == EarthNode.Kind.PLAYER },
        latitude = 0.0,
        longitude = 0.0,
        userCount = maxOf(activeCount ?: 0, 1).takeIf { kind == EarthNode.Kind.CLUSTER },
        totalWahs = 1.takeIf { kind == EarthNode.Kind.CLUSTER },
        activeCount = activeCount,
        activeUntil = activeUntil,
        isMe = isMe,
        containsMe = containsMe,
    )
}
