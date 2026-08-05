package com.azhegezhege.zhuzhiliao.ui

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.core.graphics.ColorUtils

fun Context.dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

fun View.setPaddingDp(horizontal: Int, vertical: Int) =
    setPadding(context.dp(horizontal), context.dp(vertical), context.dp(horizontal), context.dp(vertical))

fun glassDrawable(theme: SeasonTheme, radius: Float, stronger: Boolean = false): GradientDrawable =
    GradientDrawable(
        GradientDrawable.Orientation.TL_BR,
        intArrayOf(
            ColorUtils.setAlphaComponent(theme.colors.panel, if (stronger) 208 else 164),
            ColorUtils.setAlphaComponent(theme.colors.skyBottom, if (stronger) 188 else 132),
        ),
    ).apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = radius
        setStroke(1, Color.argb(42, 255, 255, 255))
    }

fun textView(
    context: Context,
    text: CharSequence = "",
    size: Float = 14f,
    color: Int = Color.WHITE,
    weight: Int = Typeface.NORMAL,
): TextView = TextView(context).apply {
    this.text = text
    textSize = size
    setTextColor(color)
    typeface = Typeface.create(Typeface.SANS_SERIF, weight)
    includeFontPadding = false
}

fun ViewGroup.add(view: View, width: Int = ViewGroup.LayoutParams.WRAP_CONTENT, height: Int = ViewGroup.LayoutParams.WRAP_CONTENT) {
    addView(view, ViewGroup.LayoutParams(width, height))
}
