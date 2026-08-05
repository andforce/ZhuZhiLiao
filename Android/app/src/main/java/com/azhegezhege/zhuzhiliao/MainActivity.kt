package com.azhegezhege.zhuzhiliao

import android.animation.ValueAnimator
import android.content.Intent
import android.os.Bundle
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.azhegezhege.zhuzhiliao.earth.EarthActivity
import com.azhegezhege.zhuzhiliao.rendering.ToyGLSurfaceView
import com.azhegezhege.zhuzhiliao.ui.ExperienceHudView
import com.azhegezhege.zhuzhiliao.ui.ReadabilityScrimView
import com.azhegezhege.zhuzhiliao.ui.SafetyIntroductionView
import com.azhegezhege.zhuzhiliao.ui.SeasonThemeStore
import com.azhegezhege.zhuzhiliao.ui.showLeaderboard
import com.azhegezhege.zhuzhiliao.ui.showThemePicker

class MainActivity : AppCompatActivity() {
    private val coordinator by lazy { (application as ZhuZhiLiaoApplication).coordinator }
    private lateinit var themeStore: SeasonThemeStore
    private lateinit var surface: ToyGLSurfaceView
    private lateinit var hud: ExperienceHudView
    private lateinit var scrim: ReadabilityScrimView
    private var safety: SafetyIntroductionView? = null
    private var bottomInset = 0
    private var pointerAccepted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        themeStore = SeasonThemeStore(this)
        val theme = themeStore.selectedTheme
        val root = FrameLayout(this)
        surface = ToyGLSurfaceView(this).apply {
            configure(coordinator, theme)
            contentDescription = "竹知了互动场景，按住并沿屏幕画圈可用手指控制"
            setOnTouchListener(::handlePointer)
        }
        scrim = ReadabilityScrimView(this).apply {
            this.theme = theme
            isClickable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        hud = ExperienceHudView(
            this,
            theme,
            onTheme = {
                showThemePicker(this, themeStore) { selected ->
                    surface.setTheme(selected, animated = ValueAnimator.areAnimatorsEnabled())
                    scrim.theme = selected
                    hud.applyTheme(selected)
                }
            },
            onEarth = {
                startActivity(Intent(this, EarthActivity::class.java).putExtra(EarthActivity.EXTRA_THEME, themeStore.selectedTheme.name))
            },
            onLeaderboard = { showLeaderboard(this, coordinator, themeStore.selectedTheme) },
            onCalibrate = coordinator::recalibrate,
        )
        root.addView(surface, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        root.addView(scrim, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        root.addView(hud, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        if (!getSharedPreferences("zhuzhiliao", MODE_PRIVATE).getBoolean(KEY_SAFETY, false)) {
            safety = SafetyIntroductionView(this, theme) {
                getSharedPreferences("zhuzhiliao", MODE_PRIVATE).edit().putBoolean(KEY_SAFETY, true).apply()
                safety?.let(root::removeView)
                safety = null
                coordinator.recalibrate()
            }.also { root.addView(it, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)) }
        }
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            bottomInset = bars.bottom
            hud.setInsets(bars.top, bars.bottom)
            safety?.setInsets(bars.top, bars.bottom)
            insets
        }
        coordinator.stateListener = { state -> runOnUiThread { hud.render(state) } }
        hud.render(coordinator.uiState)
    }

    override fun onResume() {
        super.onResume()
        surface.onResume()
    }

    override fun onPause() {
        surface.onPause()
        super.onPause()
    }

    override fun onDestroy() {
        coordinator.stateListener = null
        super.onDestroy()
    }

    private fun handlePointer(view: View, event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                pointerAccepted = event.y >= 0f && event.y < view.height - bottomInset
                if (pointerAccepted) coordinator.movePointer(event.x, event.y, view.width.toFloat(), view.height.toFloat())
            }
            MotionEvent.ACTION_MOVE -> if (pointerAccepted) {
                coordinator.movePointer(event.x, event.y, view.width.toFloat(), view.height.toFloat())
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> if (pointerAccepted) {
                coordinator.endPointerInteraction()
                pointerAccepted = false
            }
        }
        return pointerAccepted || event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL
    }

    companion object { private const val KEY_SAFETY = "zzl_safety_intro_seen" }
}
