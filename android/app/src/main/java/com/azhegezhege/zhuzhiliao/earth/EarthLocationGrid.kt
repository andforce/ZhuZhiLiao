package com.azhegezhege.zhuzhiliao.earth

import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

object EarthLocationGrid {
    const val CELL_SIZE_KILOMETERS = 20.0
    const val LATITUDE_STEP = CELL_SIZE_KILOMETERS / 111.32

    fun cellID(latitude: Double, longitude: Double): String? {
        if (latitude !in -90.0..90.0 || longitude !in -180.0..180.0) return null
        val latitudeBandCount = ceil(180.0 / LATITUDE_STEP).toInt()
        val latitudeIndex = floor((latitude + 90.0) / LATITUDE_STEP)
            .toInt()
            .coerceIn(0, latitudeBandCount - 1)
        val centerLatitude = min(
            90.0 - LATITUDE_STEP / 2.0,
            -90.0 + (latitudeIndex + 0.5) * LATITUDE_STEP,
        )
        val circumference = 40_075.0 * max(cos(centerLatitude * PI / 180.0), 0.0)
        val longitudeBandCount = max(1, (circumference / CELL_SIZE_KILOMETERS).roundToInt())
        val normalizedLongitude = if (longitude == 180.0) -180.0 else longitude
        val longitudeIndex = floor((normalizedLongitude + 180.0) / 360.0 * longitudeBandCount)
            .toInt()
            .coerceIn(0, longitudeBandCount - 1)
        return "v1:$latitudeIndex:$longitudeIndex"
    }
}
