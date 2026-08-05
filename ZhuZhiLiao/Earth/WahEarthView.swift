import SwiftUI
import UIKit

struct WahEarthView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var coordinator: ExperienceCoordinator
    let theme: SeasonTheme

    @State private var model: EarthFeatureModel
    @State private var presentedSheet: EarthSheet?
    @State private var isAutoRotationEnabled = true
    @AppStorage("zzl_earth_audio_muted") private var isAudioMuted = false

    init(coordinator: ExperienceCoordinator, theme: SeasonTheme) {
        self.coordinator = coordinator
        self.theme = theme
        _model = State(initialValue: EarthFeatureModel(coordinator: coordinator))
    }

    var body: some View {
        ZStack {
            EarthMetalSurface(
                nodes: model.nodes,
                serverClockOffsetMilliseconds: model.serverClockOffsetMilliseconds,
                localWahAt: coordinator.lastLocalWahAt,
                reduceMotion: reduceMotion,
                isAutoRotationEnabled: isAutoRotationEnabled,
                onDetailChange: model.setDetail,
                onSelect: { model.selectedNode = $0 }
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.42), .clear, .black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            chrome
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task { await model.start() }
        .onAppear {
            coordinator.setEarthPresented(true)
            coordinator.setEarthAudioMuted(isAudioMuted)
            model.startAudio()
        }
        .onDisappear {
            model.stopAudio()
            coordinator.setEarthPresented(false)
        }
        .onChange(of: coordinator.earthRevision) { _, _ in
            model.refreshForRevision()
        }
        .onChange(of: coordinator.lastLocalWahAt) { _, _ in
            model.synchronizeAudio()
        }
        .onChange(of: isAudioMuted) { _, isMuted in
            coordinator.setEarthAudioMuted(isMuted)
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .join:
                EarthJoinSheet(
                    theme: theme,
                    isWorking: model.isUpdatingLocation,
                    join: {
                        Task {
                            await model.joinWithCurrentLocation()
                            presentedSheet = nil
                        }
                    }
                )
            }
        }
        .alert("退出哇声地球？", isPresented: $model.showsLeaveConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除位置并退出", role: .destructive) {
                Task { await model.leaveEarth() }
            }
        } message: {
            Text("你的地球圆点和约 20 公里格网位置会从服务器删除，排行榜成绩不受影响。")
        }
    }

    private var chrome: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("关闭哇声地球")

                VStack(alignment: .leading, spacing: 2) {
                    Text("哇声地球")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("拖动旋转 · 双指缩放")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.58))
                }

                Spacer()

                Button {
                    isAutoRotationEnabled.toggle()
                } label: {
                    Image(systemName: isAutoRotationEnabled ? "pause.circle" : "play.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(isAutoRotationEnabled ? "停止地球自转" : "继续地球自转")
                .accessibilityValue(isAutoRotationEnabled ? "正在自转" : "已停止")

                Button {
                    isAudioMuted.toggle()
                } label: {
                    Image(systemName: isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(isAudioMuted ? "开启哇声地球声音" : "静音哇声地球")
                .accessibilityValue(isAudioMuted ? "已静音" : "声音已开启")

                if model.isParticipating {
                    Menu {
                        Button("更新我的位置", systemImage: "location") {
                            presentedSheet = .join
                        }
                        Button("退出哇声地球", systemImage: "location.slash", role: .destructive) {
                            model.showsLeaveConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("哇声地球选项")
                }
            }
            .foregroundStyle(.white)

            Spacer()

            bottomPanel
        }
        .safeAreaPadding(.horizontal, 18)
        .safeAreaPadding(.vertical, 12)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if let selected = model.selectedNode {
            HStack(spacing: 14) {
                Circle()
                    .fill(selected.highlightsMe ? theme.colors.highlight : theme.colors.accent)
                    .frame(width: 12, height: 12)
                    .shadow(color: theme.colors.accent.opacity(0.7), radius: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedTitle(selected))
                        .font(.subheadline.weight(.semibold))
                    Text("\(selected.displayedWahs.formatted()) 哇")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Button { model.selectedNode = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.58))
                }
                .accessibilityLabel("关闭圆点详情")
            }
            .padding(16)
            .seasonalGlass(theme: theme, cornerRadius: 22)
        } else if case let .failed(message) = model.loadState {
            HStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                Text(message)
                    .font(.caption)
                    .lineLimit(2)
                Spacer()
                Button("重试", action: model.retry)
                    .font(.caption.weight(.bold))
            }
            .padding(16)
            .seasonalGlass(theme: theme, cornerRadius: 22)
        } else if !model.isParticipating {
            VStack(alignment: .leading, spacing: 10) {
                Text("在地球上点亮我")
                    .font(.headline)
                Text("加入后只上传约 20 公里格网。你的每次哇声会从圆点扩散 10 分钟。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                Button {
                    presentedSheet = .join
                } label: {
                    Label("加入哇声地球", systemImage: "location.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.colors.accent)
            }
            .padding(16)
            .seasonalGlass(theme: theme, cornerRadius: 22)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(theme.colors.highlight)
                VStack(alignment: .leading, spacing: 2) {
                    Text("摇动竹知了，让这里产生回响")
                        .font(.subheadline.weight(.semibold))
                    Text("最后一声后的波纹和声音会持续 10 分钟")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
            }
            .padding(16)
            .seasonalGlass(theme: theme, cornerRadius: 22)
        }
    }

    private func selectedTitle(_ node: EarthNode) -> String {
        if node.kind == .cluster {
            return node.highlightsMe
                ? "我所在的 \(node.displayedUsers) 人共鸣"
                : "\(node.displayedUsers) 人共鸣"
        }
        if node.highlightsMe { return "我" }
        return "玩家·\(node.code ?? node.id)"
    }
}

private enum EarthSheet: String, Identifiable {
    case join
    var id: String { rawValue }
}

private struct EarthJoinSheet: View {
    @Environment(\.dismiss) private var dismiss
    let theme: SeasonTheme
    let isWorking: Bool
    let join: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(theme.colors.accent)

                Text("用一个模糊圆点加入全球共鸣")
                    .font(.title2.bold())

                Label("坐标会先在 iPhone 上量化成约 20 公里格网", systemImage: "square.grid.3x3")
                Label("服务器不会收到或保存原始精确坐标", systemImage: "lock.shield")
                Label("退出地球即可删除格网位置", systemImage: "trash")

                Spacer()

                Button {
                    join()
                } label: {
                    if isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("继续并允许使用期间定位").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.colors.accent)
                .disabled(isWorking)
            }
            .padding(24)
            .navigationTitle("加入哇声地球")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview("哇声地球") {
    WahEarthView(coordinator: ExperienceCoordinator(), theme: .summer)
}
