package com.azhegezhege.zhuzhiliao.earth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EarthJoinPresentationTest {
    @Test
    fun `locating keeps the sheet visible with explicit progress`() {
        val presentation = EarthJoinPresentation.from(
            EarthFeatureState(isUpdatingLocation = true),
        )

        assertEquals("正在获取粗略位置…", presentation.buttonLabel)
        assertFalse(presentation.buttonEnabled)
        assertEquals("正在定位，可能需要十几秒", presentation.statusMessage)
    }

    @Test
    fun `location failure stays actionable in the join sheet`() {
        val presentation = EarthJoinPresentation.from(
            EarthFeatureState(joinError = "当前无法获取位置，请稍后再试"),
        )

        assertEquals("重试定位", presentation.buttonLabel)
        assertTrue(presentation.buttonEnabled)
        assertEquals("当前无法获取位置，请稍后再试", presentation.statusMessage)
    }
}
