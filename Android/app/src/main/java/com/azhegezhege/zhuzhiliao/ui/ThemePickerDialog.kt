package com.azhegezhege.zhuzhiliao.ui

import android.app.Dialog
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.material.bottomsheet.BottomSheetDialog

fun showThemePicker(
    context: Context,
    store: SeasonThemeStore,
    onSelected: (SeasonTheme) -> Unit,
): Dialog {
    val dialog = BottomSheetDialog(context)

    fun build(): View = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(context.dp(20), context.dp(22), context.dp(20), context.dp(22))
        addView(LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(textView(context, "四时之景", 27f).apply { typeface = Typeface.create(Typeface.SERIF, Typeface.NORMAL) })
                addView(textView(context, "选择属于此刻的竹知了", 14f, 0xFFAAAAAA.toInt()))
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            addView(textView(context, "完成", 14f, 0xFFFFFFFF.toInt(), Typeface.BOLD).apply {
                setPaddingDp(12, 8); isClickable = true; setOnClickListener { dialog.dismiss() }
            })
        })
        val grid = GridLayout(context).apply { columnCount = 2; rowCount = 2 }
        SeasonTheme.entries.forEach { theme ->
            val selected = store.selectedTheme == theme
            val card = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPaddingDp(11, 11)
                background = glassDrawable(theme, context.dp(20).toFloat()).also {
                    if (selected) it.setStroke(context.dp(2), theme.colors.accent)
                }
                addView(ThemeMiniatureView(context, theme), LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, context.dp(82)))
                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    addView(LinearLayout(context).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(textView(context, theme.fullName, 14f, 0xFFFFFFFF.toInt(), Typeface.BOLD))
                        addView(textView(context, theme.tagline, 11f, 0x9EFFFFFF.toInt()))
                    }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                    addView(textView(context, if (selected) "●" else "○", 18f, if (selected) theme.colors.accent else 0x52FFFFFF.toInt(), Typeface.BOLD))
                }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = context.dp(10) })
                isClickable = true
                contentDescription = "${theme.fullName}，${theme.tagline}"
                isSelected = selected
                setOnClickListener {
                    store.select(theme)
                    onSelected(theme)
                    dialog.setContentView(build())
                }
            }
            grid.addView(card, GridLayout.LayoutParams().apply {
                width = 0
                height = GridLayout.LayoutParams.WRAP_CONTENT
                columnSpec = GridLayout.spec(GridLayout.UNDEFINED, 1f)
                setMargins(context.dp(6), context.dp(6), context.dp(6), context.dp(6))
            })
        }
        addView(grid, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = context.dp(12) })
        addView(textView(context, "主题会同时改变天空、季节意象、竹知了光泽与运动轨迹。", 12f, 0xFF999999.toInt()).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = context.dp(12) })
    }

    dialog.setContentView(build())
    dialog.show()
    return dialog
}

private class ThemeMiniatureView(context: Context, private val theme: SeasonTheme) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    override fun onDraw(canvas: Canvas) {
        val radius = context.dp(13).toFloat()
        canvas.save()
        canvas.clipRect(0f, 0f, width.toFloat(), height.toFloat())
        paint.shader = LinearGradient(0f, 0f, width.toFloat(), height.toFloat(), theme.colors.skyTop, theme.colors.skyBottom, Shader.TileMode.CLAMP)
        canvas.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), radius, radius, paint)
        paint.shader = null
        paint.color = theme.colors.highlight
        canvas.drawCircle(width * 0.78f, height * 0.28f, context.dp(16).toFloat(), paint)
        paint.color = theme.colors.accent
        repeat(7) { index ->
            val x = ((index * 31) % 112) / 112f * width
            val y = ((index * 23) % 64) / 64f * height
            canvas.drawCircle(x, y, if (index % 3 == 0) context.dp(2).toFloat() else context.resources.displayMetrics.density, paint)
        }
        paint.textAlign = Paint.Align.CENTER; paint.textSize = context.dp(28).toFloat(); paint.typeface = Typeface.DEFAULT
        canvas.drawText(theme.symbol, width / 2f, height / 2f + context.dp(10), paint)
        canvas.restore()
    }
}
