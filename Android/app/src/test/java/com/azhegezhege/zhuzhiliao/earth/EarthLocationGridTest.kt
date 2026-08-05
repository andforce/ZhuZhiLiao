package com.azhegezhege.zhuzhiliao.earth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EarthLocationGridTest {
    @Test
    fun nearbyCoordinatesShareAnAnonymousTwentyKilometerCell() {
        val first = EarthLocationGrid.cellID(31.2304, 121.4737)!!
        val nearby = EarthLocationGrid.cellID(31.2310, 121.4740)!!
        assertEquals(first, nearby)
        assertTrue(first.startsWith("v1:"))
        assertFalse(first.contains("31.2304"))
        assertNull(EarthLocationGrid.cellID(91.0, 0.0))
    }
}
