package com.azhegezhege.zhuzhiliao.ui

import android.content.Context
import com.azhegezhege.zhuzhiliao.math.Vec4
import java.time.LocalDate

enum class SeasonTheme(
    val displayName: String,
    val fullName: String,
    val tagline: String,
    val symbol: String,
    val shaderIndex: Float,
    val colors: SeasonColors,
    val palette: SeasonPalette,
) {
    SPRING(
        "春", "春日新芽", "桃影入青岚", "❀", 0f,
        SeasonColors(rgb(0.025f, 0.105f, 0.100f), rgb(0.135f, 0.285f, 0.235f), rgb(0.025f, 0.115f, 0.105f), rgb(1f, 0.455f, 0.570f), rgb(0.455f, 0.745f, 0.480f), rgb(0.945f, 0.850f, 0.650f)),
        SeasonPalette(
            v(0.018f, 0.075f, 0.070f), v(0.055f, 0.175f, 0.150f), v(0.155f, 0.320f, 0.250f), v(0.400f, 0.650f, 0.470f), v(1f, 0.390f, 0.520f), v(0.010f, 0.045f, 0.035f), v(0.56f, 0.46f, 0.18f), v(0.88f, 0.73f, 0.41f), v(0.88f, 0.76f, 0.48f, 0.97f), v(0.67f, 0.10f, 0.13f), v(0.84f, 0.24f, 0.26f), v(0.82f, 0.72f, 0.50f, 0.90f), v(1f, 0.48f, 0.58f), v(0.64f, 0.88f, 0.76f), v(1f, 0.68f, 0.54f),
        ),
    ),
    SUMMER(
        "夏", "夏夜流萤", "竹风送流萤", "✦", 1f,
        SeasonColors(rgb(0.008f, 0.090f, 0.140f), rgb(0.030f, 0.275f, 0.365f), rgb(0.015f, 0.105f, 0.150f), rgb(0.220f, 0.850f, 0.755f), rgb(0.250f, 0.610f, 0.720f), rgb(1f, 0.820f, 0.390f)),
        SeasonPalette(
            v(0.004f, 0.055f, 0.095f), v(0.012f, 0.145f, 0.205f), v(0.035f, 0.300f, 0.380f), v(0.100f, 0.630f, 0.610f), v(1f, 0.810f, 0.310f), v(0.006f, 0.045f, 0.060f), v(0.58f, 0.44f, 0.17f), v(0.85f, 0.74f, 0.39f), v(0.86f, 0.73f, 0.43f, 0.97f), v(0.70f, 0.07f, 0.08f), v(0.80f, 0.15f, 0.15f), v(0.70f, 0.79f, 0.58f, 0.90f), v(0.23f, 0.92f, 0.76f), v(0.35f, 0.80f, 0.88f), v(1f, 0.84f, 0.42f),
        ),
    ),
    AUTUMN(
        "秋", "秋山照月", "金叶映山月", "◆", 2f,
        SeasonColors(rgb(0.115f, 0.035f, 0.055f), rgb(0.410f, 0.155f, 0.085f), rgb(0.150f, 0.055f, 0.045f), rgb(0.940f, 0.450f, 0.205f), rgb(0.705f, 0.185f, 0.105f), rgb(0.965f, 0.795f, 0.460f)),
        SeasonPalette(
            v(0.075f, 0.018f, 0.030f), v(0.245f, 0.070f, 0.045f), v(0.480f, 0.205f, 0.080f), v(0.860f, 0.390f, 0.120f), v(1f, 0.690f, 0.270f), v(0.075f, 0.018f, 0.020f), v(0.62f, 0.38f, 0.11f), v(0.91f, 0.65f, 0.27f), v(0.88f, 0.67f, 0.34f, 0.97f), v(0.62f, 0.075f, 0.025f), v(0.78f, 0.18f, 0.055f), v(0.84f, 0.64f, 0.37f, 0.90f), v(1f, 0.59f, 0.22f), v(0.87f, 0.63f, 0.42f), v(1f, 0.52f, 0.18f),
        ),
    ),
    WINTER(
        "冬", "冬雪静枝", "疏枝落新雪", "❄", 3f,
        SeasonColors(rgb(0.014f, 0.035f, 0.095f), rgb(0.190f, 0.245f, 0.365f), rgb(0.035f, 0.060f, 0.135f), rgb(0.385f, 0.730f, 0.925f), rgb(0.295f, 0.425f, 0.680f), rgb(0.920f, 0.855f, 0.675f)),
        SeasonPalette(
            v(0.010f, 0.022f, 0.062f), v(0.030f, 0.060f, 0.130f), v(0.180f, 0.220f, 0.335f), v(0.300f, 0.455f, 0.690f), v(0.845f, 0.920f, 1f), v(0.006f, 0.012f, 0.034f), v(0.58f, 0.43f, 0.19f), v(0.84f, 0.70f, 0.41f), v(0.84f, 0.74f, 0.53f, 0.97f), v(0.68f, 0.08f, 0.10f), v(0.76f, 0.16f, 0.18f), v(0.75f, 0.73f, 0.62f, 0.90f), v(0.48f, 0.80f, 1f), v(0.54f, 0.70f, 1f), v(0.94f, 0.82f, 0.62f),
        ),
    );

    companion object {
        fun forMonth(month: Int): SeasonTheme = when (month) {
            in 3..5 -> SPRING
            in 6..8 -> SUMMER
            in 9..11 -> AUTUMN
            else -> WINTER
        }

        fun current(): SeasonTheme = forMonth(LocalDate.now().monthValue)
    }
}

data class SeasonColors(
    val skyTop: Int,
    val skyBottom: Int,
    val panel: Int,
    val accent: Int,
    val secondaryAccent: Int,
    val highlight: Int,
)

data class SeasonPalette(
    val skyTop: Vec4,
    val skyMiddle: Vec4,
    val skyBottom: Vec4,
    val atmosphere: Vec4,
    val seasonalAccent: Vec4,
    val silhouette: Vec4,
    val bamboo: Vec4,
    val cutBamboo: Vec4,
    val paleBamboo: Vec4,
    val lacquer: Vec4,
    val cord: Vec4,
    val rope: Vec4,
    val effect: Vec4,
    val coolLight: Vec4,
    val warmLight: Vec4,
)

class SeasonThemeStore(context: Context) {
    private val preferences = context.getSharedPreferences("zhuzhiliao", Context.MODE_PRIVATE)
    var selectedTheme: SeasonTheme = preferences.getString(KEY, null)
        ?.let { stored -> SeasonTheme.entries.firstOrNull { it.name.lowercase() == stored } }
        ?: SeasonTheme.current().also { preferences.edit().putString(KEY, it.name.lowercase()).apply() }
        private set

    fun select(theme: SeasonTheme) {
        if (selectedTheme == theme) return
        selectedTheme = theme
        preferences.edit().putString(KEY, theme.name.lowercase()).apply()
    }

    companion object { const val KEY = "zzl_selected_season" }
}

private fun rgb(r: Float, g: Float, b: Float): Int {
    val red = (r * 255f).toInt().coerceIn(0, 255)
    val green = (g * 255f).toInt().coerceIn(0, 255)
    val blue = (b * 255f).toInt().coerceIn(0, 255)
    return (0xFF shl 24) or (red shl 16) or (green shl 8) or blue
}

private fun v(x: Float, y: Float, z: Float, w: Float = 1f) = Vec4(x, y, z, w)
