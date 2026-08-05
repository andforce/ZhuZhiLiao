package com.azhegezhege.zhuzhiliao.rendering

import android.content.Context
import android.opengl.GLSurfaceView
import android.util.AttributeSet
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import com.azhegezhege.zhuzhiliao.network.EarthNode
import com.azhegezhege.zhuzhiliao.ui.dp

class EarthGLSurfaceView @JvmOverloads constructor(
    context: Context,
    attributes: AttributeSet? = null,
) : GLSurfaceView(context, attributes) {
    private var earthRenderer: EarthRenderer? = null
    private var lastX = 0f
    private var lastY = 0f
    private var dragged = false
    private val scaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: ScaleGestureDetector): Boolean {
            queueEvent { earthRenderer?.handleScale(detector.scaleFactor) }
            return true
        }
    })
    private val tapDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(event: MotionEvent): Boolean = true
        override fun onSingleTapUp(event: MotionEvent): Boolean {
            if (!dragged) {
                performClick()
                queueEvent { earthRenderer?.handleTap(event.x, event.y, context.dp(30).toFloat()) }
            }
            return true
        }
    })

    init {
        setEGLContextClientVersion(3)
        preserveEGLContextOnPause = true
        isFocusable = true
        contentDescription = "可旋转缩放的哇声地球，圆点代表匿名玩家"
    }

    fun configure(
        onDetailChange: (Int) -> Unit,
        onSelect: (EarthNode?) -> Unit,
    ) {
        earthRenderer = EarthRenderer(
            context.applicationContext,
            onDetailChange = { detail -> post { onDetailChange(detail) } },
            onSelect = { node -> post { onSelect(node) } },
        ).also(::setRenderer)
        renderMode = RENDERMODE_CONTINUOUSLY
    }

    fun update(
        nodes: List<EarthNode>,
        serverClockOffsetMilliseconds: Long,
        localWahAt: Long?,
        reduceMotion: Boolean,
        autoRotationEnabled: Boolean,
    ) = queueEvent {
        earthRenderer?.update(nodes, serverClockOffsetMilliseconds, localWahAt, reduceMotion, autoRotationEnabled)
    }

    fun setAutoRotation(enabled: Boolean) = queueEvent { earthRenderer?.setAutoRotation(enabled) }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        scaleDetector.onTouchEvent(event)
        tapDetector.onTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                lastX = event.x
                lastY = event.y
                dragged = false
            }
            MotionEvent.ACTION_POINTER_DOWN -> dragged = true
            MotionEvent.ACTION_MOVE -> {
                val deltaX = event.x - lastX
                val deltaY = event.y - lastY
                if (!scaleDetector.isInProgress && (dragged || hypotSquared(deltaX, deltaY) > context.dp(2) * context.dp(2))) {
                    dragged = true
                    queueEvent { earthRenderer?.handlePan(deltaX, deltaY) }
                }
                lastX = event.x
                lastY = event.y
            }
        }
        return true
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    private fun hypotSquared(x: Float, y: Float) = x * x + y * y
}
