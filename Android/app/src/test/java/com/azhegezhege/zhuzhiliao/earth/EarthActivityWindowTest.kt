package com.azhegezhege.zhuzhiliao.earth

import org.junit.Assert.assertEquals
import org.junit.Test

class EarthActivityWindowTest {
    @Test
    fun `a local wah remains visually active for ten minutes`() {
        assertEquals(1_780_000_600_000L, EarthActivityWindow.activeUntil(1_780_000_000_000L))
    }
}
