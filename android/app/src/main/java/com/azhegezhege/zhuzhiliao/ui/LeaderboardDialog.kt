package com.azhegezhege.zhuzhiliao.ui

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.graphics.drawable.toDrawable
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.azhegezhege.zhuzhiliao.ExperienceCoordinator
import com.azhegezhege.zhuzhiliao.network.LeaderboardEntry
import com.azhegezhege.zhuzhiliao.network.LeaderboardSnapshot
import com.google.android.material.R as MaterialR
import com.google.android.material.bottomsheet.BottomSheetDialog
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale

fun showLeaderboard(
    activity: AppCompatActivity,
    coordinator: ExperienceCoordinator,
    theme: SeasonTheme,
) {
    val dialog = BottomSheetDialog(activity)
    val content = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(activity.dp(22), activity.dp(8), activity.dp(22), activity.dp(24))
    }
    val scroll = ScrollView(activity).apply {
        isFillViewport = true
        overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
        addView(
            content,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
    }
    val refresh = SwipeRefreshLayout(activity).apply {
        setColorSchemeColors(theme.colors.accent)
        setProgressBackgroundColorSchemeColor(theme.colors.panel)
        addView(
            scroll,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }
    val status = textView(activity, "正在载入排名…", 14f, 0xB8FFFFFF.toInt()).apply {
        gravity = Gravity.CENTER
        setPaddingDp(28, 28)
        isClickable = true
    }
    val body = FrameLayout(activity).apply {
        addView(
            refresh,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        addView(
            status,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }
    val root = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        background = topRoundedSurface(theme.colors.skyTop, activity.dp(30).toFloat())
    }
    val handle = View(activity).apply {
        background = roundedFill(0x6EFFFFFF, activity.dp(3).toFloat())
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    root.addView(
        handle,
        LinearLayout.LayoutParams(activity.dp(36), activity.dp(5)).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            topMargin = activity.dp(8)
            bottomMargin = activity.dp(8)
        },
    )

    val header = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(activity.dp(22), 0, activity.dp(22), 0)
    }
    val done = textView(activity, "完成", 16f, Color.WHITE, Typeface.BOLD).apply {
        gravity = Gravity.CENTER
        background = glassDrawable(theme, activity.dp(24).toFloat(), stronger = true)
        isClickable = true
        isFocusable = true
        contentDescription = "关闭排行榜"
        setOnClickListener { dialog.dismiss() }
    }
    val title = textView(activity, "全球排行榜", 17f, Color.WHITE, Typeface.BOLD).apply {
        gravity = Gravity.CENTER
    }
    val more = textView(activity, "⋯", 23f, Color.WHITE, Typeface.BOLD).apply {
        gravity = Gravity.CENTER
        background = glassDrawable(theme, activity.dp(24).toFloat(), stronger = true)
        isClickable = true
        isFocusable = true
        contentDescription = "更多排行榜选项"
    }
    header.addView(done, LinearLayout.LayoutParams(activity.dp(72), activity.dp(48)))
    header.addView(
        title,
        LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
    )
    header.addView(
        FrameLayout(activity).apply {
            addView(
                more,
                FrameLayout.LayoutParams(activity.dp(48), activity.dp(48), Gravity.END),
            )
        },
        LinearLayout.LayoutParams(activity.dp(72), activity.dp(48)),
    )
    root.addView(header)
    root.addView(
        body,
        LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            activity.dp(500),
        ),
    )
    dialog.setContentView(root)

    var hasRenderedSnapshot = false

    fun load(showLoading: Boolean = !hasRenderedSnapshot) {
        if (showLoading) {
            status.text = "正在载入排名…"
            status.visibility = View.VISIBLE
            refresh.visibility = View.INVISIBLE
        } else {
            refresh.isRefreshing = true
        }
        activity.lifecycleScope.launch {
            runCatching { coordinator.loadLeaderboard() }
                .onSuccess { snapshot ->
                    val resetScroll = !hasRenderedSnapshot
                    renderLeaderboardContent(content, snapshot, theme)
                    hasRenderedSnapshot = true
                    status.visibility = View.GONE
                    refresh.visibility = View.VISIBLE
                    if (resetScroll) scroll.post { scroll.scrollTo(0, 0) }
                }
                .onFailure { error ->
                    status.text = buildString {
                        appendLine("暂时无法载入")
                        appendLine(error.localizedMessage ?: "网络连接失败")
                        append("点击重试")
                    }
                    status.visibility = View.VISIBLE
                    refresh.visibility = View.INVISIBLE
                }
            refresh.isRefreshing = false
        }
    }

    status.setOnClickListener { load() }
    refresh.setOnRefreshListener { load(showLoading = false) }
    more.setOnClickListener { anchor ->
        PopupMenu(activity, anchor).apply {
            menu.add("清除我的匿名数据")
            setOnMenuItemClickListener {
                AlertDialog.Builder(activity)
                    .setTitle("清除匿名数据？")
                    .setMessage("旧短码、排行榜记录、地球位置和本机个人累计都会删除，并建立一个新的零成绩匿名身份。全球聚合总数不会回退。")
                    .setNegativeButton("取消", null)
                    .setPositiveButton("清除并重置") { _, _ ->
                        activity.lifecycleScope.launch {
                            refresh.isRefreshing = true
                            runCatching { coordinator.resetAnonymousIdentity() }
                                .onSuccess { load(showLoading = false) }
                                .onFailure {
                                    status.text = it.localizedMessage ?: "重置失败，请稍后重试"
                                    status.visibility = View.VISIBLE
                                }
                        }
                    }
                    .show()
                true
            }
            show()
        }
    }
    ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
        val bottom = insets.getInsets(WindowInsetsCompat.Type.systemBars()).bottom
        view.setPadding(0, 0, 0, bottom)
        insets
    }
    dialog.setOnShowListener {
        dialog.findViewById<FrameLayout>(MaterialR.id.design_bottom_sheet)?.apply {
            background = Color.TRANSPARENT.toDrawable()
        }
        load()
    }
    dialog.show()
}

internal data class LeaderboardSections(
    val leadingEntries: List<LeaderboardEntry>,
    val separateMe: LeaderboardEntry?,
)

internal object LeaderboardPresentation {
    fun sections(snapshot: LeaderboardSnapshot): LeaderboardSections = LeaderboardSections(
        leadingEntries = snapshot.entries,
        separateMe = snapshot.me?.takeIf { me -> snapshot.entries.none { it.code == me.code } },
    )

    fun formattedScore(score: Int): String = NumberFormat
        .getIntegerInstance(Locale.US)
        .format(score)
}

private fun renderLeaderboardContent(
    content: LinearLayout,
    snapshot: LeaderboardSnapshot,
    theme: SeasonTheme,
) {
    content.removeAllViews()
    val context = content.context
    val sections = LeaderboardPresentation.sections(snapshot)
    if (sections.leadingEntries.isEmpty()) {
        content.addView(
            LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPaddingDp(20, 68)
                addView(textView(context, "♕", 36f, theme.colors.highlight).apply {
                    gravity = Gravity.CENTER
                })
                addView(textView(context, "还没有成绩", 18f, Color.WHITE, Typeface.BOLD).apply {
                    gravity = Gravity.CENTER
                })
                addView(textView(context, "转出第一声，成为榜首。", 13f, 0x99FFFFFF.toInt()).apply {
                    gravity = Gravity.CENTER
                }, topMargin(context, 8, ViewGroup.LayoutParams.MATCH_PARENT))
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
    } else {
        content.addView(
            sectionTitle(context, "累计哇声 · ${snapshot.totalPlayers} 位玩家"),
            topMargin(context, 12, ViewGroup.LayoutParams.MATCH_PARENT),
        )
        content.addView(
            leaderboardCard(
                context = context,
                entries = sections.leadingEntries,
                myCode = snapshot.me?.code,
                theme = theme,
            ),
            topMargin(context, 12, ViewGroup.LayoutParams.MATCH_PARENT),
        )
    }

    sections.separateMe?.let { me ->
        content.addView(
            sectionTitle(context, "我的名次"),
            topMargin(context, 24, ViewGroup.LayoutParams.MATCH_PARENT),
        )
        content.addView(
            leaderboardCard(context, listOf(me), myCode = me.code, theme = theme),
            topMargin(context, 12, ViewGroup.LayoutParams.MATCH_PARENT),
        )
    }
}

private fun sectionTitle(context: android.content.Context, title: String): TextView =
    textView(context, title, 16f, 0xA8FFFFFF.toInt(), Typeface.BOLD).apply {
        setPadding(context.dp(2), 0, 0, 0)
    }

private fun leaderboardCard(
    context: android.content.Context,
    entries: List<LeaderboardEntry>,
    myCode: String?,
    theme: SeasonTheme,
): LinearLayout = LinearLayout(context).apply {
    orientation = LinearLayout.VERTICAL
    background = glassDrawable(theme, context.dp(24).toFloat(), stronger = true)
    clipToOutline = true
    entries.forEachIndexed { index, entry ->
        addView(
            leaderboardRow(context, entry, entry.code == myCode, theme),
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        if (index != entries.lastIndex) {
            addView(View(context).apply {
                setBackgroundColor(0x30FFFFFF)
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1).apply {
                leftMargin = context.dp(18)
                rightMargin = context.dp(18)
            })
        }
    }
}

private fun leaderboardRow(
    context: android.content.Context,
    entry: LeaderboardEntry,
    isMe: Boolean,
    theme: SeasonTheme,
): LinearLayout = LinearLayout(context).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    minimumHeight = context.dp(if (isMe) 72 else 62)
    setPadding(context.dp(18), context.dp(11), context.dp(18), context.dp(11))

    addView(
        textView(
            context,
            "#${entry.rank}",
            17f,
            if (entry.rank <= 3) theme.colors.highlight else 0xA8FFFFFF.toInt(),
            Typeface.BOLD,
        ).apply { gravity = Gravity.START or Gravity.CENTER_VERTICAL },
        LinearLayout.LayoutParams(context.dp(62), LinearLayout.LayoutParams.WRAP_CONTENT),
    )

    addView(
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            addView(
                textView(
                    context,
                    if (isMe) "我" else "玩家·${entry.code}",
                    16f,
                    Color.WHITE,
                    if (isMe) Typeface.BOLD else Typeface.NORMAL,
                ).apply {
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                },
            )
            if (isMe) {
                addView(
                    textView(context, "玩家·${entry.code}", 12f, 0x8FFFFFFF.toInt()).apply {
                        maxLines = 1
                        ellipsize = TextUtils.TruncateAt.END
                    },
                    topMargin(context, 2),
                )
            }
        },
        LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
            rightMargin = context.dp(8)
        },
    )

    addView(
        LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            addView(
                textView(
                    context,
                    LeaderboardPresentation.formattedScore(entry.score),
                    17f,
                    Color.WHITE,
                    Typeface.BOLD,
                ).apply { gravity = Gravity.END },
            )
            addView(
                textView(context, "哇", 12f, 0x82FFFFFF.toInt()).apply {
                    gravity = Gravity.CENTER_VERTICAL
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { leftMargin = context.dp(8) },
            )
        },
        LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ),
    )
    contentDescription =
        "第 ${entry.rank} 名，${if (isMe) "我" else "玩家 ${entry.code}"}，${entry.score} 哇"
}

private fun topRoundedSurface(color: Int, radius: Float): GradientDrawable =
    GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        setColor(color)
        cornerRadii = floatArrayOf(radius, radius, radius, radius, 0f, 0f, 0f, 0f)
    }

private fun roundedFill(color: Int, radius: Float): GradientDrawable =
    GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        setColor(color)
        cornerRadius = radius
    }

private fun topMargin(
    context: android.content.Context,
    margin: Int,
    width: Int = ViewGroup.LayoutParams.WRAP_CONTENT,
): LinearLayout.LayoutParams = LinearLayout.LayoutParams(
    width,
    LinearLayout.LayoutParams.WRAP_CONTENT,
).apply { topMargin = context.dp(margin) }
