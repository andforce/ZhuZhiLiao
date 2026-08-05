package com.azhegezhege.zhuzhiliao.earth

import android.content.Context
import com.azhegezhege.zhuzhiliao.rendering.Vertex
import org.json.JSONArray
import org.json.JSONObject

object EarthBoundaryLoader {
    fun vertices(context: Context, assetName: String, radius: Float): List<Vertex> {
        val root = runCatching {
            context.assets.open("earth/$assetName.geojson").bufferedReader().use { JSONObject(it.readText()) }
        }.getOrNull() ?: return emptyList()
        val result = mutableListOf<Vertex>()
        val features = root.optJSONArray("features") ?: return result
        for (featureIndex in 0 until features.length()) {
            val geometry = features.optJSONObject(featureIndex)?.optJSONObject("geometry") ?: continue
            when (geometry.optString("type")) {
                "Polygon" -> appendPolygon(geometry.optJSONArray("coordinates"), radius, result)
                "MultiPolygon" -> {
                    val polygons = geometry.optJSONArray("coordinates") ?: continue
                    for (polygonIndex in 0 until polygons.length()) {
                        appendPolygon(polygons.optJSONArray(polygonIndex), radius, result)
                    }
                }
            }
        }
        return result
    }

    private fun appendPolygon(rings: JSONArray?, radius: Float, output: MutableList<Vertex>) {
        if (rings == null) return
        for (ringIndex in 0 until rings.length()) {
            val ring = rings.optJSONArray(ringIndex) ?: continue
            var previous: Vertex? = null
            for (pointIndex in 0 until ring.length()) {
                val coordinates = ring.optJSONArray(pointIndex) ?: continue
                if (coordinates.length() < 2) continue
                val longitude = coordinates.optDouble(0, Double.NaN)
                val latitude = coordinates.optDouble(1, Double.NaN)
                if (!longitude.isFinite() || !latitude.isFinite()) continue
                val point = EarthGeometry.spherePoint(latitude, longitude, radius)
                val normal = point.normalized()
                val vertex = Vertex(point.x, point.y, point.z, normal.x, normal.y, normal.z)
                previous?.let { output += it; output += vertex }
                previous = vertex
            }
        }
    }
}
