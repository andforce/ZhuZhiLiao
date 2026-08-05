package com.azhegezhege.zhuzhiliao.ui

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView

class SafetyIntroductionView(
    context: Context,
    private val theme: SeasonTheme,
    private val onContinue: () -> Unit,
) : FrameLayout(context) {
    private val content = LinearLayout(context)

    init {
        isClickable = true
        background = GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            intArrayOf(theme.colors.skyTop, theme.colors.skyBottom, Color.rgb(7, 6, 13)),
        )
        content.orientation = LinearLayout.VERTICAL
        content.gravity = Gravity.CENTER_HORIZONTAL
        addTopRow()
        content.addView(Space(context), LinearLayout.LayoutParams(1, 0, 0.7f))
        content.addView(SafetyOrbitView(context, theme), LinearLayout.LayoutParams(context.dp(160), context.dp(160)))
        content.addView(textView(context, "握稳手机，轻轻摇动", 31f, Color.argb(245, 255, 255, 255)).apply {
            typeface = Typeface.create(Typeface.SERIF, Typeface.NORMAL)
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = context.dp(26) })
        content.addView(textView(context, "任意方向短幅连续摇动，竹知了会自然摆动并逐渐转成圆圈。", 16f, Color.argb(163, 255, 255, 255)).apply {
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.18f)
        }, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = context.dp(9) })
        content.addView(steps(), LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = context.dp(26) })
        content.addView(Space(context), LinearLayout.LayoutParams(1, 0, 1f))
        content.addView(textView(context, "稳定起转与每完成一圈，都有触感反馈", 12f, Color.argb(122, 255, 255, 255)).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { bottomMargin = context.dp(13) })
        content.addView(TextView(context).apply {
            text = "我已握稳"
            textSize = 17f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            background = glassDrawable(theme, context.dp(18).toFloat(), stronger = true).also { it.setColor(theme.colors.accent) }
            isClickable = true
            isFocusable = true
            setOnClickListener { onContinue() }
            contentDescription = "我已握稳，开始体验"
        }, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, context.dp(54)))
        addView(content, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    fun setInsets(top: Int, bottom: Int) {
        content.setPadding(context.dp(24), top + context.dp(15), context.dp(24), bottom + context.dp(12))
    }

    private fun addTopRow() {
        content.addView(LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(textView(context, "赛博竹知了", 18f, Color.argb(235, 255, 255, 255)).apply { typeface = Typeface.create(Typeface.SERIF, Typeface.NORMAL) }, LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
            addView(textView(context, "${theme.symbol} ${theme.displayName} · 安全提示", 12f, theme.colors.highlight, Typeface.BOLD))
        }, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }

    private fun steps() = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPaddingDp(16, 16)
        background = glassDrawable(theme, context.dp(22).toFloat())
        listOf(
            "01" to "留出一臂的安全空间",
            "02" to "单手握紧 Android 手机，使用短幅动作",
            "03" to "连续轻摇即可，不需要大力挥动",
        ).forEachIndexed { index, (number, label) ->
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(textView(context, number, 12f, theme.colors.accent, Typeface.BOLD), LinearLayout.LayoutParams(context.dp(42), LayoutParams.WRAP_CONTENT))
                addView(textView(context, label, 15f, Color.argb(214, 255, 255, 255), Typeface.BOLD))
            }, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { if (index > 0) topMargin = context.dp(14) })
        }
    }
}

private class SafetyOrbitView(context: Context, private val theme: SeasonTheme) : android.view.View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val bounds = RectF()
    private var rotation = 0f
    private val animator = ValueAnimator.ofFloat(0f, 360f).apply {
        duration = 4_500
        repeatCount = ValueAnimator.INFINITE
        interpolator = null
        addUpdateListener { rotation = it.animatedValue as Float; invalidate() }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (ValueAnimator.areAnimatorsEnabled()) animator.start()
    }
    override fun onDetachedFromWindow() { animator.cancel(); super.onDetachedFromWindow() }

    override fun onDraw(canvas: Canvas) {
        val centerX = width / 2f; val centerY = height / 2f; val radius = minOf(width, height) / 2f - context.dp(3)
        bounds.set(centerX - radius, centerY - radius, centerX + radius, centerY + radius)
        paint.style = Paint.Style.STROKE; paint.strokeWidth = context.resources.displayMetrics.density
        paint.color = Color.argb(26, 255, 255, 255); canvas.drawOval(bounds, paint)
        canvas.save(); canvas.rotate(rotation, centerX, centerY)
        paint.strokeWidth = context.resources.displayMetrics.density * 2.2f; paint.strokeCap = Paint.Cap.ROUND; paint.color = theme.colors.accent
        canvas.drawArc(bounds, 14f, 270f, false, paint)
        paint.style = Paint.Style.FILL; canvas.drawCircle(centerX, centerY - radius, context.dp(6).toFloat(), paint)
        paint.color = Color.argb(150, 35, 35, 40)
        val phone = RectF(centerX - context.dp(19), centerY - context.dp(35), centerX + context.dp(19), centerY + context.dp(35))
        canvas.rotate(14f, centerX, centerY); canvas.drawRoundRect(phone, context.dp(11).toFloat(), context.dp(11).toFloat(), paint)
        paint.style = Paint.Style.STROKE; paint.strokeWidth = context.resources.displayMetrics.density; paint.color = Color.argb(76, 255, 255, 255); canvas.drawRoundRect(phone, context.dp(11).toFloat(), context.dp(11).toFloat(), paint)
        canvas.restore()
    }
}
