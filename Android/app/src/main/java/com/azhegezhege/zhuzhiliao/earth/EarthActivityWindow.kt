package com.azhegezhege.zhuzhiliao.earth

object EarthActivityWindow {
    const val DURATION_MILLISECONDS = 10L * 60L * 1_000L

    fun activeUntil(lastWahAt: Long): Long = lastWahAt + DURATION_MILLISECONDS
}
