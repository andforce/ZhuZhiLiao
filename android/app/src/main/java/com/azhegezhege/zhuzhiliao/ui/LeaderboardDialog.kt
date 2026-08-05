package com.azhegezhege.zhuzhiliao.ui

import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.PopupMenu
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.azhegezhege.zhuzhiliao.ExperienceCoordinator
import com.azhegezhege.zhuzhiliao.network.LeaderboardEntry
import com.google.android.material.bottomsheet.BottomSheetDialog
import kotlinx.coroutines.launch

fun showLeaderboard(
    activity: AppCompatActivity,
    coordinator: ExperienceCoordinator,
    theme: SeasonTheme,
) {
    val dialog = BottomSheetDialog(activity)
    val adapter = LeaderboardAdapter(theme)
    val recycler = RecyclerView(activity).apply {
        layoutManager = LinearLayoutManager(activity)
        this.adapter = adapter
        setBackgroundColor(Color.TRANSPARENT)
    }
    val refresh = SwipeRefreshLayout(activity).apply {
        setColorSchemeColors(theme.colors.accent)
        addView(recycler, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    }
    val status = textView(activity, "正在载入排名…", 14f, Color.LTGRAY).apply { gravity = Gravity.CENTER }
    val body = FrameLayout(activity).apply {
        addView(refresh, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, activity.dp(500)))
        addView(status, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, activity.dp(500)))
    }
    val root = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(theme.colors.skyTop)
    }
    val header = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPaddingDp(12, 10)
    }
    val done = textView(activity, "完成", 14f, Color.WHITE, Typeface.BOLD).apply {
        setPaddingDp(8, 8); isClickable = true; setOnClickListener { dialog.dismiss() }
    }
    val title = textView(activity, "全球排行榜", 16f, Color.WHITE, Typeface.BOLD).apply { gravity = Gravity.CENTER }
    val more = textView(activity, "⋯", 24f, Color.WHITE, Typeface.BOLD).apply {
        gravity = Gravity.CENTER; isClickable = true; contentDescription = "更多"
    }
    header.addView(done, LinearLayout.LayoutParams(activity.dp(64), activity.dp(44)))
    header.addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
    header.addView(more, LinearLayout.LayoutParams(activity.dp(64), activity.dp(44)))
    root.addView(header)
    root.addView(body)
    dialog.setContentView(root)

    fun load() {
        refresh.isRefreshing = true
        status.visibility = View.GONE
        activity.lifecycleScope.launch {
            runCatching { coordinator.loadLeaderboard() }
                .onSuccess { snapshot ->
                    val entries = snapshot.entries.toMutableList()
                    snapshot.me?.takeIf { me -> entries.none { it.code == me.code } }?.let(entries::add)
                    adapter.submit(entries, snapshot.me?.code)
                    status.text = if (entries.isEmpty()) "还没有成绩\n转出第一声，成为榜首。" else ""
                    status.visibility = if (entries.isEmpty()) View.VISIBLE else View.GONE
                    title.text = "全球排行榜 · ${snapshot.totalPlayers} 人"
                }
                .onFailure { error ->
                    status.text = "暂时无法载入\n${error.localizedMessage ?: "网络连接失败"}\n点击重试"
                    status.visibility = View.VISIBLE
                    status.setOnClickListener { load() }
                }
            refresh.isRefreshing = false
        }
    }

    refresh.setOnRefreshListener { load() }
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
                                .onSuccess { load() }
                                .onFailure { status.text = it.localizedMessage; status.visibility = View.VISIBLE }
                        }
                    }
                    .show()
                true
            }
            show()
        }
    }
    dialog.setOnShowListener { load() }
    dialog.show()
}

private class LeaderboardAdapter(private val theme: SeasonTheme) : RecyclerView.Adapter<LeaderboardRowHolder>() {
    private var entries: List<LeaderboardEntry> = emptyList()
    private var myCode: String? = null

    fun submit(values: List<LeaderboardEntry>, me: String?) {
        entries = values
        myCode = me
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): LeaderboardRowHolder =
        LeaderboardRowHolder(LinearLayout(parent.context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(parent.context.dp(18), parent.context.dp(12), parent.context.dp(18), parent.context.dp(12))
        })

    override fun getItemCount() = entries.size

    override fun onBindViewHolder(holder: LeaderboardRowHolder, position: Int) {
        val entry = entries[position]
        holder.bind(entry, entry.code == myCode, theme)
    }
}

private class LeaderboardRowHolder(private val row: LinearLayout) : RecyclerView.ViewHolder(row) {
    fun bind(entry: LeaderboardEntry, isMe: Boolean, theme: SeasonTheme) {
        row.removeAllViews()
        row.addView(textView(row.context, "#${entry.rank}", 16f, if (entry.rank <= 3) theme.colors.highlight else Color.GRAY, Typeface.BOLD), LinearLayout.LayoutParams(row.context.dp(56), LinearLayout.LayoutParams.WRAP_CONTENT))
        row.addView(LinearLayout(row.context).apply {
            orientation = LinearLayout.VERTICAL
            addView(textView(row.context, if (isMe) "我" else "玩家·${entry.code}", 15f, Color.WHITE, if (isMe) Typeface.BOLD else Typeface.NORMAL))
            if (isMe) addView(textView(row.context, "玩家·${entry.code}", 11f, Color.GRAY))
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(textView(row.context, "${entry.score}  哇", 14f, Color.WHITE, Typeface.BOLD))
        row.contentDescription = "第 ${entry.rank} 名，${if (isMe) "我" else "玩家 ${entry.code}"}，${entry.score} 哇"
    }
}
