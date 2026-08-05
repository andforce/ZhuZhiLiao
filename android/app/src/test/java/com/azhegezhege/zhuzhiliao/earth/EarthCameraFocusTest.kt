package com.azhegezhege.zhuzhiliao.earth

import com.azhegezhege.zhuzhiliao.network.EarthNode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EarthCameraFocusTest {
    @Test
    fun `preferred node keeps my location individually focused`() {
        val ordinary = node("front", latitude = 0.0, longitude = 180.0)
        val mine = node("mine", latitude = 31.2, longitude = 121.5, isMe = true)

        assertEquals(mine, EarthCameraFocus.preferredNode(listOf(ordinary, mine), EarthCameraFocus.INITIAL))
    }

    @Test
    fun `centered angles bring target to front hemisphere`() {
        val target = node("target", latitude = -33.9, longitude = 151.2)
        val angles = EarthCameraFocus.centeredAngles(target)

        assertTrue(EarthCameraFocus.frontDepth(target, angles) > 0.999f)
    }

    @Test
    fun `sphere point matches ios globe axes`() {
        assertEquals(-1f, EarthGeometry.spherePoint(0.0, 0.0).x, 0.0001f)
        assertEquals(1f, EarthGeometry.spherePoint(90.0, 0.0).y, 0.0001f)
        assertEquals(1f, EarthGeometry.spherePoint(0.0, 90.0).z, 0.0001f)
    }

    @Test
    fun `joining later refocuses the globe on my location`() {
        val tracker = EarthFocusTracker()
        val ordinary = node("front", latitude = 0.0, longitude = 180.0)
        val mine = node("mine", latitude = 31.2, longitude = 121.5, isMe = true)

        assertEquals(ordinary, tracker.nextTarget(listOf(ordinary), EarthCameraFocus.INITIAL))
        assertEquals(mine, tracker.nextTarget(listOf(ordinary, mine), EarthCameraFocus.INITIAL))
    }

    private fun node(id: String, latitude: Double, longitude: Double, isMe: Boolean = false) = EarthNode(
        kind = EarthNode.Kind.PLAYER,
        id = id,
        code = id,
        score = 1,
        latitude = latitude,
        longitude = longitude,
        userCount = null,
        totalWahs = null,
        activeCount = null,
        activeUntil = null,
        isMe = isMe,
        containsMe = false,
    )
}
