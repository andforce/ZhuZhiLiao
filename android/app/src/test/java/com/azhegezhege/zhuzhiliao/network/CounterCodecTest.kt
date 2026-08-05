package com.azhegezhege.zhuzhiliao.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CounterCodecTest {
    @Test
    fun decodesStatsPlayerAndEarthMessagesFromSharedServer() {
        assertEquals(
            CounterServerMessage.Stats(CounterStats(online = 3, wahs = 128)),
            CounterCodec.decode("""{"t":"stats","online":3,"wahs":128}"""),
        )
        val player = CounterCodec.decode(
            """{"t":"player","id":"p1","code":"A7K3M9","score":12,"migrated":true,"earthEnabled":true,"locationCell":"v1:500:1002"}""",
        ) as CounterServerMessage.Player
        assertEquals("A7K3M9", player.code)
        assertEquals(12, player.score)
        assertTrue(player.earthEnabled)

        val earth = CounterCodec.decode(
            """{"t":"earth_snapshot","requestID":"r1","serverTime":1785852800000,"revision":3,"nodes":[{"kind":"cluster","id":"d1:2:3","latitude":10.0,"longitude":20.0,"userCount":4,"totalWahs":99,"activeCount":1,"activeUntil":1785852900000,"containsMe":true}]}""",
        ) as CounterServerMessage.Earth
        assertEquals(99, earth.snapshot.nodes.single().displayedWahs)
        assertTrue(earth.snapshot.nodes.single().highlightsMe)
    }

    @Test
    fun scoreAndEarthViewMessagesPreserveServerWireShape() {
        assertEquals("{\"t\":\"score\",\"value\":30}", CounterCodec.score(30))
        assertEquals(
            "{\"t\":\"migrate\",\"personal\":20,\"pendingGlobal\":20}",
            CounterCodec.migration(personal = 20, pendingGlobal = 99),
        )
        val encoded = CounterCodec.earthView(
            "r1",
            detail = 9,
            bounds = listOf(EarthBounds(-10.0, 10.0, 20.0, 40.0)),
        )
        assertTrue(encoded.contains("\"detail\":4"))
        assertTrue(encoded.contains("\"requestID\":\"r1\""))
    }
}
