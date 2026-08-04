import SwiftUI

struct LeaderboardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coordinator: ExperienceCoordinator
    let theme: SeasonTheme

    @State private var state: LoadState = .loading
    @State private var isJoining = false
    @State private var isDeleting = false
    @State private var showsDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if !coordinator.isLeaderboardParticipant {
                    optedOutContent
                } else {
                    loadedContent
                }
            }
            .navigationTitle("全球排行榜")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                if coordinator.isLeaderboardParticipant {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("删除匿名身份并退出", role: .destructive) {
                                showsDeleteConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(isDeleting)
                    }
                }
            }
            .background(theme.colors.skyTop.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            if coordinator.isLeaderboardParticipant {
                await load()
            }
        }
        .alert("删除匿名身份？", isPresented: $showsDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除并退出", role: .destructive) {
                Task { await deleteIdentity() }
            }
        } message: {
            Text("你的公开短码和排行榜记录会被删除。本机累计数会保留；以后重新加入时会获得新的短码。")
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        switch state {
        case .loading:
            ProgressView("正在载入排名…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("暂时无法载入", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { Task { await load() } }
            }
        case let .loaded(snapshot):
            leaderboard(snapshot)
        }
    }

    private func leaderboard(_ snapshot: LeaderboardSnapshot) -> some View {
        List {
            if snapshot.entries.isEmpty {
                ContentUnavailableView(
                    "还没有成绩",
                    systemImage: "trophy",
                    description: Text("转出第一声，成为榜首。")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("累计哇声 · \(snapshot.totalPlayers) 位玩家") {
                    ForEach(snapshot.entries) { entry in
                        LeaderboardRow(
                            entry: entry,
                            isMe: entry.code == snapshot.me?.code,
                            accent: theme.colors.highlight
                        )
                    }
                }
            }

            if let me = snapshot.me,
               !snapshot.entries.contains(where: { $0.code == me.code }) {
                Section("我的名次") {
                    LeaderboardRow(entry: me, isMe: true, accent: theme.colors.highlight)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    private var optedOutContent: some View {
        ContentUnavailableView {
            Label("未加入排行榜", systemImage: "trophy")
        } description: {
            Text("加入后会生成一个匿名短码，不需要昵称或注册。")
        } actions: {
            Button(isJoining ? "正在加入…" : "加入排行榜") {
                Task { await join() }
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.colors.accent)
            .disabled(isJoining)
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await coordinator.loadLeaderboard())
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func join() async {
        isJoining = true
        defer { isJoining = false }
        do {
            try await coordinator.joinLeaderboard()
            try? await Task.sleep(for: .milliseconds(500))
            await load()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func deleteIdentity() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await coordinator.deleteLeaderboardIdentity()
            state = .loading
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private enum LoadState {
    case loading
    case loaded(LeaderboardSnapshot)
    case failed(String)
}

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let isMe: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            Text("#\(entry.rank)")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(entry.rank <= 3 ? accent : .secondary)
                .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? "我" : "玩家·\(entry.code)")
                    .font(.body.weight(isMe ? .bold : .medium))
                if isMe {
                    Text("玩家·\(entry.code)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(entry.score, format: .number)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Text("哇")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "第 \(entry.rank) 名，\(isMe ? "我" : "玩家 \(entry.code)"), \(entry.score) 哇"
        )
    }
}
