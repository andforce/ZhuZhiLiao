package com.azhegezhege.zhuzhiliao.physics

import com.azhegezhege.zhuzhiliao.math.Vec3
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ToySimulationTest {
    @Test
    fun fixedStepProducesSameResultAtSixtyAndOneHundredTwentyFramesPerSecond() {
        val sixty = ToySimulation()
        val oneTwenty = ToySimulation()
        val input = MotionInput(
            anchorAcceleration = Vec3(0.8f, -0.2f, 0.35f),
            gravityDirection = Vec3(0f, -1f, 0f),
            rotationRate = Vec3.ZERO,
        )

        repeat(120) { sixty.advance(input, 1.0 / 60.0) }
        repeat(240) { oneTwenty.advance(input, 1.0 / 120.0) }

        assertVecEquals(sixty.state.position, oneTwenty.state.position, 0.0001f)
        assertVecEquals(sixty.state.velocity, oneTwenty.state.velocity, 0.0001f)
        assertEquals(sixty.state.activity, oneTwenty.state.activity, 0.0001f)
    }

    @Test
    fun `pointer anchor motion preserves bob world inertia`() {
        val configuration = inertialConfiguration()
        val initial = ToyPhysicsState(
            position = Vec3(1f, 0f, 0f),
            velocity = Vec3.ZERO,
            ropeLength = 2f,
            angularVelocity = Vec3.ZERO,
            tension = 0f,
            activity = 0f,
        )
        val simulation = ToySimulation(configuration, initial)
        val initialWorld = initial.anchorOffset + initial.position
        simulation.advance(MotionInput(Vec3.ZERO, Vec3.ZERO, Vec3.ZERO, Vec3(0.8f, 0.2f, 0f)), 1.0 / 60.0)
        val world = simulation.state.anchorOffset + simulation.state.position
        assertVecEquals(initialWorld, world, 0.0001f)
        assertTrue(simulation.state.anchorOffset.x > 0f)
    }

    @Test
    fun `web rope keeps endpoints and reference sag`() {
        val points = WebRopeShape.points(Vec3.ZERO, Vec3(0f, -1f, 0f), ropeLength = 2f, count = 5)
        assertEquals(Vec3.ZERO, points.first())
        assertEquals(Vec3(0f, -1f, 0f), points.last())
        assertEquals(-0.98125f, points[2].y, 0.0001f)
        assertTrue(-0.75f - points[3].y > -0.25f - points[1].y)
    }

    @Test
    fun `forward phone acceleration moves toy into opposite depth`() {
        val simulation = ToySimulation(inertialConfiguration())
        simulation.advance(MotionInput(Vec3(0f, 0f, 1f), Vec3.ZERO, Vec3.ZERO), 1.0 / 60.0)
        assertTrue(simulation.state.velocity.z < 0f)
    }

    @Test
    fun `stationary input never false counts`() {
        val simulation = ToySimulation()
        var completed = 0
        val input = MotionInput(Vec3.ZERO, Vec3(0f, -1f, 0f), Vec3.ZERO)
        repeat(60 * 20) { completed += simulation.advance(input, 1.0 / 60.0).completedWahs }
        assertEquals(0, completed)
        assertTrue(simulation.state.activity < 0.01f)
    }

    private fun assertVecEquals(expected: Vec3, actual: Vec3, tolerance: Float) {
        assertEquals(expected.x, actual.x, tolerance)
        assertEquals(expected.y, actual.y, tolerance)
        assertEquals(expected.z, actual.z, tolerance)
    }

    private fun inertialConfiguration() = ToyPhysicsConfiguration(
        ropeLength = 1f,
        gravityMagnitude = 0f,
        motionAccelerationScale = 1f,
        ropeStiffness = 0f,
        ropeDamping = 0f,
        airDrag = 0f,
        maximumStretchRatio = 10f,
        orbitQualityThreshold = 0.65f,
    )
}
