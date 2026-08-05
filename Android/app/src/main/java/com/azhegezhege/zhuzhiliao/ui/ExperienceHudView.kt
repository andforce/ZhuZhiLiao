package com.azhegezhege.zhuzhiliao.ui

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.azhegezhege.zhuzhiliao.ExperienceUiState
import com.azhegezhege.zhuzhiliao.ToyInteractionState
import java.text.DecimalFormat
import java.util.Locale

class ExperienceHudView(
    context: Context,
    themeValue: SeasonTheme,
    private val onTheme: () -> Unit,
    private val onEarth: () -> Unit,
    private val onLeaderboard: () -> Unit,
    private val onCalibrate: () -> Unit,
) : FrameLayout(context) {
    private val brandTitle = textView(context, "竹知了", 25f, Color.argb(240, 255, 255, 255)).apply {
        typeface = Typeface.create(Typeface.SERIF, Typeface.NORMAL)
    }
    private val brandSeason = textView(context, "赛博童玩", 9f, themeValue.colors.highlight, Typeface.BOLD).apply { letterSpacing = 0.15f }
    private val brandTagline = textView(context, themeValue.tagline, 10f, Color.argb(143, 255, 255, 255))
    private val accentBar = View(context)
    private val themeButton = GlassIconButton(context, GlassIcon.THEME, "选择季节主题", onTheme)
    private val earthButton = GlassIconButton(context, GlassIcon.GLOBE, "哇声地球", onEarth)
    private val leaderboardButton = GlassIconButton(context, GlassIcon.RANKING, "排行榜", onLeaderboard)
    private val calibrateButton = GlassIconButton(context, GlassIcon.CALIBRATE, "重新定位", onCalibrate)
    private val speedLabel = textView(context, "当前转速", 11f, Color.argb(142, 255, 255, 255), Typeface.BOLD).apply { letterSpacing = 0.10f }
    private val speedValue = textView(context, "0.0", 42f).apply {
        typeface = Typeface.create(Typeface.SERIF, Typeface.NORMAL)
    }
    private val instructionPanel = LinearLayout(context)
    private val instructionGlyph = OrbitGlyphView(context)
    private val instructionTitle = textView(context, "轻轻往复摇动手机", 15f, Color.argb(245, 255, 255, 255), Typeface.BOLD)
    private val instructionDetail = textView(context, "任意方向短幅连续摇动 · 也可按住屏幕滑动", 12f, Color.argb(153, 255, 255, 255))
    private val statValues = List(3) { textView(context, "0", 12f, Color.argb(214, 255, 255, 255), Typeface.BOLD).apply { gravity = Gravity.CENTER } }
    private val statLabels = listOf("此刻在线", "全球共鸣", "我的哇声")
    private val statsPanel = LinearLayout(context)
    private var theme = themeValue

    init {
        isClickable = false
        addHeader()
        addDashboard()
        applyTheme(theme)
    }

    fun setInsets(top: Int, bottom: Int) {
        setPadding(context.dp(18), top + context.dp(10), context.dp(18), bottom + context.dp(10))
    }

    fun render(state: ExperienceUiState) {
        speedValue.text = String.format(Locale.US, "%.1f", state.revolutionsPerSecond)
        instructionTitle.text = state.interactionState.title
        instructionDetail.text = state.interactionState.detail
        instructionGlyph.setActive(state.interactionState in setOf(
            ToyInteractionState.SHAKING,
            ToyInteractionState.SPINNING,
            ToyInteractionState.TOUCHING,
            ToyInteractionState.AUTOMATIC,
        ))
        statValues[0].text = compact(state.stats.online)
        statValues[1].text = compact(state.stats.wahs)
        statValues[2].text = compact(state.personalWahs)
        contentDescription = "在线 ${state.stats.online} 人，全球 ${state.stats.wahs} 哇，我转出了 ${state.personalWahs} 哇"
    }

    fun applyTheme(value: SeasonTheme) {
        theme = value
        themeButton.contentDescription = "选择季节主题，当前是${value.displayName}季"
        brandSeason.setTextColor(value.colors.highlight)
        brandTagline.text = value.tagline
        listOf(themeButton, earthButton, leaderboardButton, calibrateButton).forEach { it.applyTheme(value) }
        accentBar.setBackgroundColor(value.colors.accent)
        speedValue.setTextColor(value.colors.highlight)
        instructionPanel.background = glassDrawable(value, context.dp(20).toFloat())
        instructionGlyph.applyTheme(value)
        statsPanel.background = glassDrawable(value, context.dp(18).toFloat())
    }

    private fun addHeader() {
        val header = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP or Gravity.CENTER_VERTICAL
        }
        val brand = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(brandTitle)
            addView(accentBar, LinearLayout.LayoutParams(context.dp(2), context.dp(30)).apply { setMargins(context.dp(8), 0, context.dp(8), 0) })
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(brandSeason)
                addView(brandTagline)
            })
        }
        header.addView(brand, LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
        val actions = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            addView(themeButton, iconParams())
            addView(earthButton, iconParams().apply { marginStart = context.dp(7) })
            addView(leaderboardButton, iconParams().apply { marginStart = context.dp(7) })
        }
        header.addView(actions)
        addView(header, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { gravity = Gravity.TOP })
    }

    private fun addDashboard() {
        val dashboard = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        val speedRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.BOTTOM
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(speedLabel)
                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.BOTTOM
                    addView(speedValue)
                    addView(textView(context, "圈/秒", 12f, Color.argb(158, 255, 255, 255), Typeface.BOLD).apply {
                        setPadding(0, 0, 0, context.dp(7))
                    })
                })
            }, LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
            addView(calibrateButton, iconParams())
        }
        dashboard.addView(speedRow)
        instructionPanel.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPaddingDp(15, 10)
            addView(instructionGlyph, LinearLayout.LayoutParams(context.dp(38), context.dp(38)))
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(instructionTitle)
                addView(instructionDetail.apply { maxLines = 2 })
            }, LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = context.dp(13) })
        }
        dashboard.addView(instructionPanel, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, context.dp(66)).apply { topMargin = context.dp(12) })
        statsPanel.apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, context.dp(10), 0, context.dp(10))
            statValues.forEachIndexed { index, value ->
                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER
                    addView(value, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
                    addView(textView(context, statLabels[index], 10f, Color.argb(117, 255, 255, 255)).apply { gravity = Gravity.CENTER })
                }, LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
                if (index < 2) addView(View(context).apply { setBackgroundColor(Color.argb(33, 255, 255, 255)) }, LinearLayout.LayoutParams(1, context.dp(24)).apply { gravity = Gravity.CENTER_VERTICAL })
            }
        }
        dashboard.addView(statsPanel, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = context.dp(12) })
        addView(dashboard, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { gravity = Gravity.BOTTOM })
    }

    private fun iconParams() = LinearLayout.LayoutParams(context.dp(44), context.dp(44))

    private fun compact(value: Int): String = when {
        value >= 1_000_000 -> DecimalFormat("0.#M").format(value / 1_000_000.0)
        value >= 1_000 -> DecimalFormat("0.#K").format(value / 1_000.0)
        else -> value.toString()
    }
}

private enum class GlassIcon { THEME, GLOBE, RANKING, CALIBRATE }

private class GlassIconButton(
    context: Context,
    private val icon: GlassIcon,
    description: String,
    click: () -> Unit,
) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val bounds = RectF()
    private val path = Path()
    private var theme = SeasonTheme.current()

    init {
        isClickable = true
        isFocusable = true
        contentDescription = description
        setOnClickListener { click() }
    }

    fun applyTheme(value: SeasonTheme) {
        theme = value
        background = glassDrawable(value, context.dp(22).toFloat())
        invalidate()
    }

    override fun drawableStateChanged() {
        super.drawableStateChanged()
        alpha = if (isPressed) 0.72f else 1f
    }

    override fun getAccessibilityClassName(): CharSequence = android.widget.Button::class.java.name

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f
        val radius = minOf(width, height) * 0.22f
        paint.color = Color.argb(230, 255, 255, 255)
        paint.strokeWidth = resources.displayMetrics.density * 1.55f
        paint.style = Paint.Style.STROKE
        when (icon) {
            GlassIcon.GLOBE -> drawGlobe(canvas, cx, cy, radius)
            GlassIcon.RANKING -> drawRanking(canvas, cx, cy, radius)
            GlassIcon.CALIBRATE -> drawCalibrate(canvas, cx, cy, radius)
            GlassIcon.THEME -> drawTheme(canvas, cx, cy, radius)
        }
    }

    private fun drawGlobe(canvas: Canvas, cx: Float, cy: Float, radius: Float) {
        canvas.drawCircle(cx, cy, radius, paint)
        bounds.set(cx - radius * 0.48f, cy - radius, cx + radius * 0.48f, cy + radius)
        canvas.drawOval(bounds, paint)
        bounds.set(cx - radius, cy - radius * 0.42f, cx + radius, cy + radius * 0.42f)
        canvas.drawOval(bounds, paint)
    }

    private fun drawRanking(canvas: Canvas, cx: Float, cy: Float, radius: Float) {
        val left = cx - radius
        val right = cx + radius
        for (index in -1..1) {
            val y = cy + index * radius * 0.68f
            paint.style = Paint.Style.FILL
            canvas.drawCircle(left, y, paint.strokeWidth * 0.7f, paint)
            paint.style = Paint.Style.STROKE
            canvas.drawLine(left + radius * 0.35f, y, right, y, paint)
        }
    }

    private fun drawCalibrate(canvas: Canvas, cx: Float, cy: Float, radius: Float) {
        canvas.drawCircle(cx, cy, radius * 0.55f, paint)
        canvas.drawCircle(cx, cy, paint.strokeWidth * 0.7f, paint)
        val inner = radius * 0.74f
        val outer = radius * 1.14f
        canvas.drawLine(cx, cy - outer, cx, cy - inner, paint)
        canvas.drawLine(cx, cy + inner, cx, cy + outer, paint)
        canvas.drawLine(cx - outer, cy, cx - inner, cy, paint)
        canvas.drawLine(cx + inner, cy, cx + outer, cy, paint)
    }

    private fun drawTheme(canvas: Canvas, cx: Float, cy: Float, radius: Float) {
        paint.color = theme.colors.highlight
        when (theme) {
            SeasonTheme.SPRING -> {
                paint.style = Paint.Style.FILL
                repeat(5) { index ->
                    val angle = Math.toRadians((index * 72.0) - 90.0)
                    canvas.drawCircle(
                        cx + kotlin.math.cos(angle).toFloat() * radius * 0.55f,
                        cy + kotlin.math.sin(angle).toFloat() * radius * 0.55f,
                        radius * 0.36f,
                        paint,
                    )
                }
                paint.color = theme.colors.panel
                canvas.drawCircle(cx, cy, radius * 0.24f, paint)
            }
            SeasonTheme.SUMMER -> {
                paint.style = Paint.Style.STROKE
                repeat(4) { index ->
                    canvas.save()
                    canvas.rotate(index * 45f, cx, cy)
                    canvas.drawLine(cx, cy - radius, cx, cy + radius, paint)
                    canvas.restore()
                }
                paint.style = Paint.Style.FILL
                canvas.drawCircle(cx, cy, radius * 0.18f, paint)
            }
            SeasonTheme.AUTUMN -> {
                path.reset()
                path.moveTo(cx - radius * 0.78f, cy + radius * 0.65f)
                path.cubicTo(cx - radius, cy - radius * 0.25f, cx - radius * 0.18f, cy - radius, cx + radius * 0.85f, cy - radius * 0.76f)
                path.cubicTo(cx + radius * 0.52f, cy + radius * 0.14f, cx - radius * 0.08f, cy + radius * 0.8f, cx - radius * 0.78f, cy + radius * 0.65f)
                paint.style = Paint.Style.FILL
                canvas.drawPath(path, paint)
                paint.color = theme.colors.panel
                paint.style = Paint.Style.STROKE
                canvas.drawLine(cx - radius * 0.64f, cy + radius * 0.56f, cx + radius * 0.56f, cy - radius * 0.56f, paint)
            }
            SeasonTheme.WINTER -> {
                paint.style = Paint.Style.STROKE
                repeat(3) { index ->
                    canvas.save()
                    canvas.rotate(index * 60f, cx, cy)
                    canvas.drawLine(cx, cy - radius, cx, cy + radius, paint)
                    canvas.restore()
                }
                canvas.drawCircle(cx, cy, radius * 0.16f, paint)
            }
        }
    }
}

private class OrbitGlyphView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val bounds = RectF()
    private var active = false
    private var angle = 0f
    private var theme = SeasonTheme.current()
    private val animator = ValueAnimator.ofFloat(0f, 360f).apply {
        duration = 2_200
        repeatCount = ValueAnimator.INFINITE
        interpolator = null
        addUpdateListener { angle = it.animatedValue as Float; invalidate() }
    }

    fun setActive(value: Boolean) {
        if (active == value) return
        active = value
        if (active && ValueAnimator.areAnimatorsEnabled()) {
            animator.start()
        } else {
            animator.cancel()
            angle = 0f
            invalidate()
        }
    }

    fun applyTheme(value: SeasonTheme) { theme = value; invalidate() }

    override fun onDraw(canvas: Canvas) {
        val center = width / 2f; val radius = minOf(width, height) * 0.39f
        bounds.set(center - radius, height / 2f - radius, center + radius, height / 2f + radius)
        paint.strokeWidth = context.dp(1).toFloat(); paint.color = Color.argb(51, 255, 255, 255)
        canvas.drawOval(bounds, paint)
        canvas.save(); canvas.rotate(angle, center, height / 2f)
        paint.strokeWidth = context.resources.displayMetrics.density * 1.8f
        paint.strokeCap = Paint.Cap.ROUND
        paint.color = if (active) theme.colors.accent else Color.argb(97, 255, 255, 255)
        canvas.drawArc(bounds, 18f, 234f, false, paint)
        dotPaint.color = theme.colors.highlight
        canvas.drawCircle(center, height / 2f - radius, context.dp(3).toFloat(), dotPaint)
        canvas.restore()
    }

    override fun onDetachedFromWindow() { animator.cancel(); super.onDetachedFromWindow() }
}
