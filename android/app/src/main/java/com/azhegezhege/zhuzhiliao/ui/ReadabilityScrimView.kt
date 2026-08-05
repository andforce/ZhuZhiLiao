package com.azhegezhege.zhuzhiliao.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.view.View

class ReadabilityScrimView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    var theme: SeasonTheme = SeasonTheme.current()
        set(value) { field = value; invalidate() }

    override fun onDraw(canvas: Canvas) {
        val topHeight = context.dp(168).toFloat()
        paint.shader = LinearGradient(
            0f, 0f, 0f, topHeight,
            intArrayOf(withAlpha(theme.colors.skyTop, 148), Color.TRANSPARENT),
            null,
            Shader.TileMode.CLAMP,
        )
        canvas.drawRect(0f, 0f, width.toFloat(), topHeight, paint)
        val bottomHeight = context.dp(340).toFloat()
        paint.shader = LinearGradient(
            0f, height - bottomHeight, 0f, height.toFloat(),
            intArrayOf(Color.TRANSPARENT, withAlpha(theme.colors.panel, 72), Color.argb(194, 0, 0, 0)),
            floatArrayOf(0f, 0.3f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawRect(0f, height - bottomHeight, width.toFloat(), height.toFloat(), paint)
        paint.shader = null
    }

    private fun withAlpha(color: Int, alpha: Int) = Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
}
