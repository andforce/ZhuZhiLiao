import SwiftUI

struct ExperienceHUD: View {
    @ObservedObject var coordinator: ExperienceCoordinator
    let theme: SeasonTheme
    let showThemePicker: () -> Void
    let showEarth: () -> Void
    let showLeaderboard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ExperienceHeader(
                theme: theme,
                showThemePicker: showThemePicker,
                showEarth: showEarth,
                showLeaderboard: showLeaderboard
            )

            Spacer(minLength: 210)

            ExperienceDashboard(
                coordinator: coordinator,
                theme: theme,
                recalibrate: coordinator.recalibrate
            )
        }
        .safeAreaPadding(.horizontal, 18)
        .safeAreaPadding(.top, 10)
        .safeAreaPadding(.bottom, 10)
    }
}

private struct ExperienceHeader: View {
    let theme: SeasonTheme
    let showThemePicker: () -> Void
    let showEarth: () -> Void
    let showLeaderboard: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row {
                BrandLockup(theme: theme)
            }
            row {
                Text("竹知了")
                    .font(.custom("Songti SC", size: 23, relativeTo: .title2))
                    .foregroundStyle(.white.opacity(0.94))
                    .fixedSize()
                    .accessibilityLabel("赛博竹知了")
            }
        }
    }

    private func row<Brand: View>(@ViewBuilder brand: () -> Brand) -> some View {
        HStack(alignment: .top, spacing: 8) {
            brand()
            Spacer(minLength: 2)
            actions
        }
    }

    private var actions: some View {
        SeasonalGlassGroup(spacing: 7) {
            HStack(spacing: 7) {
                    HeaderActionButton(
                        title: theme.displayName,
                        symbol: theme.symbolName,
                        theme: theme,
                        action: showThemePicker
                    )
                    .accessibilityLabel("选择季节主题，当前是\(theme.displayName)季")

                    HeaderActionButton(
                        title: "地球",
                        symbol: "globe.asia.australia.fill",
                        theme: theme,
                        action: showEarth
                    )
                    .accessibilityLabel("哇声地球")
                    .accessibilityHint("查看世界各地的哇声和两分钟共鸣波纹")

                    HeaderActionButton(
                        title: "排行",
                        symbol: "trophy",
                        theme: theme,
                        action: showLeaderboard
                    )
                    .accessibilityLabel("排行榜")
                    .accessibilityHint("查看全球累计排行榜和我的名次")
            }
        }
    }
}

private struct BrandLockup: View {
    let theme: SeasonTheme

    var body: some View {
        HStack(spacing: 8) {
            Text("竹知了")
                .font(.custom("Songti SC", size: 25, relativeTo: .title2))
                .foregroundStyle(Color.white.opacity(0.94))
                .fixedSize()

            Rectangle()
                .fill(theme.colors.accent)
                .frame(width: 2, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("赛博童玩")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(theme.colors.highlight)
                    .fixedSize()

                Text(theme.tagline)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .fixedSize()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
        .shadow(color: .black.opacity(0.26), radius: 8, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("赛博竹知了，\(theme.fullName)，\(theme.tagline)")
    }
}

private struct HeaderActionButton: View {
    let title: String
    let symbol: String
    let theme: SeasonTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.90))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .seasonalGlass(theme: theme, cornerRadius: 22, interactive: true)
        .fixedSize()
    }
}

private struct ExperienceDashboard: View {
    @ObservedObject var coordinator: ExperienceCoordinator
    let theme: SeasonTheme
    let recalibrate: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom) {
                SpeedReadout(
                    revolutionsPerSecond: coordinator.revolutionsPerSecond,
                    theme: theme
                )

                Spacer(minLength: 12)

                HeaderActionButton(
                    title: "校准",
                    symbol: "scope",
                    theme: theme,
                    action: recalibrate
                )
                .accessibilityLabel("重新定位")
                .accessibilityHint("把当前握持方向设为新的起始方向")
            }
            .frame(maxWidth: .infinity)

            InstructionPanel(state: coordinator.interactionState, theme: theme)

            StatisticsBar(
                online: coordinator.stats.online,
                globalWahs: coordinator.stats.wahs,
                personalWahs: coordinator.personalWahs,
                theme: theme
            )
        }
    }
}

private struct SpeedReadout: View {
    let revolutionsPerSecond: Float
    let theme: SeasonTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("当前转速")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.56))
                .textCase(.uppercase)
                .tracking(1.4)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(revolutionsPerSecond, format: .number.precision(.fractionLength(1)))
                    .font(.custom("Songti SC", size: 42, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.highlight)
                    .contentTransition(.numericText())

                Text("圈/秒")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("每秒转动 \(String(format: "%.1f", revolutionsPerSecond)) 圈")
    }
}

private struct InstructionPanel: View {
    let state: ToyInteractionState
    let theme: SeasonTheme

    var body: some View {
        HStack(spacing: 13) {
            OrbitInstructionGlyph(state: state, theme: theme)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.instructionTitle)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))

                Text(state.instructionDetail)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(.white.opacity(0.60))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 66)
        .seasonalGlass(theme: theme, cornerRadius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.instructionTitle)，\(state.instructionDetail)")
    }
}

private struct OrbitInstructionGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: ToyInteractionState
    let theme: SeasonTheme
    @State private var rotation = 0.0

    private var isActive: Bool {
        switch state {
        case .shaking, .spinning, .touching, .automatic: true
        case .idle, .unavailable: false
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.20), lineWidth: 1)

            Circle()
                .trim(from: 0.05, to: 0.70)
                .stroke(
                    isActive ? theme.colors.accent : .white.opacity(0.38),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )

            Circle()
                .fill(theme.colors.highlight)
                .frame(width: 6, height: 6)
                .offset(y: -15)
        }
        .frame(width: 30, height: 30)
        .rotationEffect(.degrees(rotation))
        .frame(width: 38, height: 38)
        .onAppear(perform: updateAnimation)
        .onChange(of: state) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        guard isActive, !reduceMotion else {
            rotation = 0
            return
        }
        rotation = 0
        withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

private struct StatisticsBar: View {
    let online: Int
    let globalWahs: Int
    let personalWahs: Int
    let theme: SeasonTheme

    var body: some View {
        HStack(spacing: 0) {
            Statistic(label: "此刻在线", value: online)
            divider
            Statistic(label: "全球共鸣", value: globalWahs)
            divider
            Statistic(label: "我的哇声", value: personalWahs)
        }
        .padding(.vertical, 10)
        .contentTransition(.numericText())
        .seasonalGlass(theme: theme, cornerRadius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("在线 \(online) 人，全球 \(globalWahs) 哇，我转出了 \(personalWahs) 哇")
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.13))
            .frame(width: 0.5, height: 24)
    }
}

private struct Statistic: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(value, format: .number.notation(.compactName))
                .font(.system(.caption, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.84))

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.46))
        }
        .frame(maxWidth: .infinity)
    }
}

extension ToyInteractionState {
    var instructionTitle: String {
        switch self {
        case .idle: "轻轻往复摇动手机"
        case .shaking: "已感应，继续摇动"
        case .spinning: "竹知了已经转起来了"
        case .touching: "正在用手指控制"
        case .automatic: "正在自动演示"
        case .unavailable: "按住屏幕滑动"
        }
    }

    var instructionDetail: String {
        switch self {
        case .idle: "任意方向短幅连续摇动 · 也可按住屏幕滑动"
        case .shaking: "正在蓄力成圈 · 不需要大幅甩动"
        case .spinning: "持续摇动会转得更快、叫得更响"
        case .touching: "沿屏幕连续画圈 · 松手后恢复动作控制"
        case .automatic: "触摸屏幕后可切换为手指控制"
        case .unavailable: "动作传感器不可用 · 请沿屏幕连续画圈"
        }
    }
}
