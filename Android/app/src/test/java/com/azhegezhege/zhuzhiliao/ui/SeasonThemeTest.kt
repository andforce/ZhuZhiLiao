package com.azhegezhege.zhuzhiliao.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SeasonThemeTest {
    @Test
    fun `month mapping covers all season boundaries`() {
        assertEquals(SeasonTheme.WINTER, SeasonTheme.forMonth(2))
        assertEquals(SeasonTheme.SPRING, SeasonTheme.forMonth(3))
        assertEquals(SeasonTheme.SPRING, SeasonTheme.forMonth(5))
        assertEquals(SeasonTheme.SUMMER, SeasonTheme.forMonth(6))
        assertEquals(SeasonTheme.SUMMER, SeasonTheme.forMonth(8))
        assertEquals(SeasonTheme.AUTUMN, SeasonTheme.forMonth(9))
        assertEquals(SeasonTheme.AUTUMN, SeasonTheme.forMonth(11))
        assertEquals(SeasonTheme.WINTER, SeasonTheme.forMonth(12))
    }

    @Test
    fun `every theme has stable unique identity and finite palette`() {
        assertEquals(4, SeasonTheme.entries.map { it.shaderIndex }.toSet().size)
        SeasonTheme.entries.forEach { theme ->
            val values = listOf(
                theme.palette.skyTop,
                theme.palette.skyMiddle,
                theme.palette.skyBottom,
                theme.palette.bamboo,
                theme.palette.effect,
            ).flatMap { listOf(it.x, it.y, it.z, it.w) }
            assertTrue(values.all(Float::isFinite))
        }
    }
}
