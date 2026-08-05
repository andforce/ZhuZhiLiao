package com.azhegezhege.zhuzhiliao.earth

import android.Manifest
import android.animation.ValueAnimator
import android.content.pm.PackageManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import com.azhegezhege.zhuzhiliao.ZhuZhiLiaoApplication
import com.azhegezhege.zhuzhiliao.network.EarthNode
import com.azhegezhege.zhuzhiliao.rendering.EarthGLSurfaceView
import com.azhegezhege.zhuzhiliao.ui.SeasonTheme
import com.azhegezhege.zhuzhiliao.ui.dp
import com.azhegezhege.zhuzhiliao.ui.glassDrawable
import com.azhegezhege.zhuzhiliao.ui.setPaddingDp
import com.azhegezhege.zhuzhiliao.ui.textView
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.button.MaterialButton
import java.text.NumberFormat

class EarthActivity : AppCompatActivity() {
    private val coordinator by lazy { (application as ZhuZhiLiaoApplication).coordinator }
    private val locationService by lazy { EarthLocationService(this) }
    private lateinit var theme: SeasonTheme
    private lateinit var surface: EarthGLSurfaceView
    private lateinit var model: EarthFeatureModel
    private lateinit var root: FrameLayout
    private lateinit var topBar: LinearLayout
    private lateinit var bottomContainer: FrameLayout
    private lateinit var autoButton: View
    private lateinit var optionsButton: View
    private var autoRotationEnabled = true
    private var pendingLocationRequest = false
    private var joinDialog: BottomSheetDialog? = null
    private var joinActionButton: MaterialButton? = null
    private var joinStatusView: TextView? = null

    private val permissionLauncher = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (pendingLocationRequest) {
            pendingLocationRequest = false
            if (granted) performJoin()
            else {
                joinDialog?.dismiss()
                model.showError("没有位置权限，你仍然可以浏览哇声地球")
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        theme = intent.getStringExtra(EXTRA_THEME)?.let { name -> SeasonTheme.entries.firstOrNull { it.name == name } }
            ?: SeasonTheme.current()
        root = FrameLayout(this)
        surface = EarthGLSurfaceView(this).apply {
            configure(
                onDetailChange = { if (::model.isInitialized) model.setDetail(it) },
                onSelect = { if (::model.isInitialized) model.select(it) },
            )
        }
        root.addView(surface, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        root.addView(EarthChromeScrim(this), FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        buildChrome()
        setContentView(root)
        model = EarthFeatureModel(coordinator, lifecycleScope, ::render)
        coordinator.earthRevisionListener = { model.refreshForRevision() }
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            topBar.setPadding(dp(18), bars.top + dp(12), dp(18), dp(6))
            (bottomContainer.layoutParams as FrameLayout.LayoutParams).apply {
                leftMargin = dp(18); rightMargin = dp(18); bottomMargin = bars.bottom + dp(12)
                bottomContainer.layoutParams = this
            }
            insets
        }
        model.start()
        model.refreshExistingLocation(locationService)
    }

    override fun onResume() {
        super.onResume()
        surface.onResume()
    }

    override fun onStart() {
        super.onStart()
        coordinator.setEarthPresented(true)
    }

    override fun onPause() {
        surface.onPause()
        super.onPause()
    }

    override fun onStop() {
        coordinator.setEarthPresented(false)
        super.onStop()
    }

    override fun onDestroy() {
        coordinator.earthRevisionListener = null
        model.close()
        super.onDestroy()
    }

    private fun buildChrome() {
        topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val close = chromeButton("×", "关闭哇声地球") { finish() }
        val heading = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(textView(this@EarthActivity, "哇声地球", 17f, Color.WHITE, android.graphics.Typeface.BOLD))
            addView(textView(this@EarthActivity, "拖动旋转 · 双指缩放", 11f, 0x94FFFFFF.toInt()))
        }
        autoButton = chromeButton("Ⅱ", "停止地球自转") { toggleAutoRotation() }
        optionsButton = chromeButton("⋯", "哇声地球选项") { anchor -> showOptions(anchor) }.apply { visibility = View.GONE }
        topBar.addView(close, LinearLayout.LayoutParams(dp(44), dp(44)))
        topBar.addView(heading, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { leftMargin = dp(8) })
        topBar.addView(autoButton, LinearLayout.LayoutParams(dp(44), dp(44)))
        topBar.addView(optionsButton, LinearLayout.LayoutParams(dp(44), dp(44)))
        root.addView(topBar, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP))

        bottomContainer = FrameLayout(this)
        root.addView(bottomContainer, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM).apply {
            leftMargin = dp(18); rightMargin = dp(18); bottomMargin = dp(12)
        })
    }

    private fun render(state: EarthFeatureState) {
        surface.update(
            state.nodes,
            state.serverClockOffsetMilliseconds,
            coordinator.lastLocalWahMillis,
            reduceMotion = !ValueAnimator.areAnimatorsEnabled(),
            autoRotationEnabled = autoRotationEnabled,
        )
        optionsButton.visibility = if (state.isParticipating) View.VISIBLE else View.GONE
        renderJoinSheet(state)
        bottomContainer.removeAllViews()
        bottomContainer.addView(buildBottomPanel(state), FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    }

    private fun buildBottomPanel(state: EarthFeatureState): View {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = glassDrawable(theme, dp(22).toFloat(), stronger = true)
            setPaddingDp(16, 16)
        }
        when {
            state.selectedNode != null -> buildSelectedPanel(panel, state.selectedNode)
            state.error != null -> {
                val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
                row.addView(textView(this, "⌁", 22f, Color.WHITE), LinearLayout.LayoutParams(dp(36), ViewGroup.LayoutParams.WRAP_CONTENT))
                row.addView(textView(this, state.error, 12f, 0xC7FFFFFF.toInt()).apply { maxLines = 2 }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                row.addView(textView(this, "重试", 12f, Color.WHITE, android.graphics.Typeface.BOLD).apply {
                    setPaddingDp(12, 10); isClickable = true; setOnClickListener { model.retry() }
                })
                panel.addView(row)
            }
            !state.isParticipating -> {
                panel.addView(textView(this, "在地球上点亮我", 17f, Color.WHITE, android.graphics.Typeface.BOLD))
                panel.addView(textView(this, "加入后只上传约 20 公里格网。你的每次哇声会从圆点扩散 10 分钟。", 12f, 0x9EFFFFFF.toInt()), marginTop(8))
                panel.addView(accentButton("◎  加入哇声地球") { showJoinSheet() }, marginTop(12, ViewGroup.LayoutParams.MATCH_PARENT))
            }
            else -> {
                val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
                row.addView(textView(this, "◉", 24f, theme.colors.highlight), LinearLayout.LayoutParams(dp(42), ViewGroup.LayoutParams.WRAP_CONTENT))
                row.addView(LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(textView(this@EarthActivity, "摇动竹知了，让这里产生回响", 14f, Color.WHITE, android.graphics.Typeface.BOLD))
                    addView(textView(this@EarthActivity, "最后一声后的波纹会持续 10 分钟", 11f, 0x94FFFFFF.toInt()))
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                panel.addView(row)
            }
        }
        return panel
    }

    private fun buildSelectedPanel(panel: LinearLayout, node: EarthNode) {
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        row.addView(textView(this, "●", 18f, if (node.highlightsMe) theme.colors.highlight else theme.colors.accent), LinearLayout.LayoutParams(dp(30), ViewGroup.LayoutParams.WRAP_CONTENT))
        row.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val title = when {
                node.kind == EarthNode.Kind.CLUSTER && node.highlightsMe -> "我所在的 ${node.displayedUsers} 人共鸣"
                node.kind == EarthNode.Kind.CLUSTER -> "${node.displayedUsers} 人共鸣"
                node.highlightsMe -> "我"
                else -> "玩家·${node.code ?: node.id}"
            }
            addView(textView(this@EarthActivity, title, 14f, Color.WHITE, android.graphics.Typeface.BOLD))
            addView(textView(this@EarthActivity, "${NumberFormat.getIntegerInstance().format(node.displayedWahs)} 哇", 12f, 0x9EFFFFFF.toInt()))
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(chromeButton("⊗", "关闭圆点详情") { model.select(null) }, LinearLayout.LayoutParams(dp(44), dp(44)))
        panel.addView(row)
    }

    private fun toggleAutoRotation() {
        autoRotationEnabled = !autoRotationEnabled
        surface.setAutoRotation(autoRotationEnabled)
        (autoButton as? android.widget.TextView)?.apply {
            text = if (autoRotationEnabled) "Ⅱ" else "▶"
            contentDescription = if (autoRotationEnabled) "停止地球自转" else "继续地球自转"
            ViewCompat.setStateDescription(this, if (autoRotationEnabled) "正在自转" else "已停止")
        }
    }

    private fun showOptions(anchor: View) {
        PopupMenu(this, anchor).apply {
            menu.add("更新我的位置")
            menu.add("退出哇声地球")
            setOnMenuItemClickListener { item ->
                when (item.title.toString()) {
                    "更新我的位置" -> showJoinSheet()
                    else -> confirmLeave()
                }
                true
            }
            show()
        }
    }

    private fun showJoinSheet() {
        val dialog = BottomSheetDialog(this)
        joinDialog = dialog
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPaddingDp(24, 24)
            setBackgroundColor(theme.colors.skyTop)
            addView(textView(this@EarthActivity, "◎", 48f, theme.colors.accent))
            addView(textView(this@EarthActivity, "加入哇声地球", 16f, Color.WHITE, android.graphics.Typeface.BOLD), marginTop(4))
            addView(textView(this@EarthActivity, "用一个模糊圆点加入全球共鸣", 22f, Color.WHITE, android.graphics.Typeface.BOLD), marginTop(16))
            addView(textView(this@EarthActivity, "▦  坐标会先在 Android 手机上量化成约 20 公里格网", 14f, Color.WHITE), marginTop(22))
            addView(textView(this@EarthActivity, "▣  服务器不会收到或保存原始精确坐标", 14f, Color.WHITE), marginTop(14))
            addView(textView(this@EarthActivity, "♲  退出地球即可删除格网位置", 14f, Color.WHITE), marginTop(14))
            val status = textView(this@EarthActivity, "", 12f, theme.colors.highlight).apply {
                gravity = Gravity.CENTER
                visibility = View.GONE
            }
            joinStatusView = status
            addView(status, marginTop(18, ViewGroup.LayoutParams.MATCH_PARENT))
            val action = accentButton("继续并允许使用期间定位") { requestLocationAndJoin() }
            joinActionButton = action
            addView(action, marginTop(10, ViewGroup.LayoutParams.MATCH_PARENT))
            addView(textView(this@EarthActivity, "取消", 14f, Color.WHITE, android.graphics.Typeface.BOLD).apply {
                gravity = Gravity.CENTER; setPaddingDp(8, 14); isClickable = true; setOnClickListener { dialog.dismiss() }
            }, marginTop(6, ViewGroup.LayoutParams.MATCH_PARENT))
        }
        dialog.setContentView(content)
        dialog.setOnDismissListener {
            if (joinDialog === dialog) {
                joinDialog = null
                joinActionButton = null
                joinStatusView = null
            }
        }
        dialog.show()
        renderJoinSheet(model.state)
    }

    private fun requestLocationAndJoin() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            performJoin()
        } else {
            pendingLocationRequest = true
            permissionLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
    }

    private fun performJoin() {
        model.join(locationService) { succeeded ->
            if (succeeded) joinDialog?.dismiss()
        }
    }

    private fun renderJoinSheet(state: EarthFeatureState) {
        val presentation = EarthJoinPresentation.from(state)
        joinActionButton?.apply {
            text = presentation.buttonLabel
            isEnabled = presentation.buttonEnabled
        }
        joinStatusView?.apply {
            text = presentation.statusMessage.orEmpty()
            visibility = if (presentation.statusMessage == null) View.GONE else View.VISIBLE
        }
    }

    private fun confirmLeave() {
        AlertDialog.Builder(this)
            .setTitle("退出哇声地球？")
            .setMessage("你的地球圆点和约 20 公里格网位置会从服务器删除，排行榜成绩不受影响。")
            .setNegativeButton("取消", null)
            .setPositiveButton("清除位置并退出") { _, _ -> model.leave() }
            .show()
    }

    private fun chromeButton(label: String, description: String, action: (View) -> Unit): View =
        textView(this, label, 20f, Color.WHITE, android.graphics.Typeface.BOLD).apply {
            gravity = Gravity.CENTER
            isClickable = true
            isFocusable = true
            contentDescription = description
            setOnClickListener(action)
        }

    private fun accentButton(label: String, action: () -> Unit): MaterialButton = MaterialButton(this).apply {
        text = label
        setTextColor(Color.WHITE)
        backgroundTintList = android.content.res.ColorStateList.valueOf(theme.colors.accent)
        cornerRadius = dp(16)
        setOnClickListener { action() }
    }

    private fun marginTop(top: Int, width: Int = ViewGroup.LayoutParams.WRAP_CONTENT) =
        LinearLayout.LayoutParams(width, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(top) }

    companion object { const val EXTRA_THEME = "season_theme" }
}

private class EarthChromeScrim(context: android.content.Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    init { isClickable = false; importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO }

    override fun onDraw(canvas: Canvas) {
        paint.shader = LinearGradient(
            0f,
            0f,
            0f,
            height.toFloat(),
            intArrayOf(0xA8000000.toInt(), Color.TRANSPARENT, 0xC2000000.toInt()),
            floatArrayOf(0f, 0.48f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
    }
}
