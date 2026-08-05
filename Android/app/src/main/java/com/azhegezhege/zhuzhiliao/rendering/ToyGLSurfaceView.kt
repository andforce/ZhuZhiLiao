package com.azhegezhege.zhuzhiliao.rendering

import android.content.Context
import android.opengl.GLSurfaceView
import android.util.AttributeSet
import com.azhegezhege.zhuzhiliao.ExperienceCoordinator
import com.azhegezhege.zhuzhiliao.ui.SeasonTheme

class ToyGLSurfaceView @JvmOverloads constructor(
    context: Context,
    attributes: AttributeSet? = null,
) : GLSurfaceView(context, attributes) {
    private var toyRenderer: ToyRenderer? = null

    init {
        setEGLContextClientVersion(3)
        preserveEGLContextOnPause = true
    }

    fun configure(coordinator: ExperienceCoordinator, theme: SeasonTheme) {
        toyRenderer = ToyRenderer(coordinator, theme).also(::setRenderer)
        renderMode = RENDERMODE_CONTINUOUSLY
    }

    fun setTheme(theme: SeasonTheme, animated: Boolean = true) {
        queueEvent { toyRenderer?.setTheme(theme, animated) }
    }
}
