package com.azhegezhege.zhuzhiliao.motion

import com.azhegezhege.zhuzhiliao.math.Quaternion
import com.azhegezhege.zhuzhiliao.math.Vec3
import com.azhegezhege.zhuzhiliao.physics.ToySimulation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MotionCoordinateMapperTest {
    @Test
    fun `portrait sensor gravity maps below the calibrated anchor`() {
        val gravity = MotionCoordinateMapper.sceneGravity(
            sensorGravity = MotionCoordinateMapper.DEFAULT_SENSOR_GRAVITY,
            deviceToCalibratedScene = Quaternion.IDENTITY,
        )

        assertEquals(0f, gravity.x, 0.0001f)
        assertTrue("gravity must point below the anchor", gravity.y < -0.999f)
        assertEquals(0f, gravity.z, 0.0001f)

        val simulation = ToySimulation()
        simulation.reset(gravity)
        assertTrue("recalibration must reset the toy below its anchor", simulation.state.position.y < 0f)
    }
}
