import SwiftUI

struct ContentView: View {
    @ObservedObject var coordinator: ExperienceCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("zzl_safety_intro_seen") private var hasSeenSafetyIntroduction = false
    private let isRunningUnitTests = ProcessInfo.processInfo.environment[
        "XCTestConfigurationFilePath"
    ] != nil

    var body: some View {
        ZStack {
            if isRunningUnitTests {
                Color.clear
            } else {
                GeometryReader { proxy in
                    MetalSurface(coordinator: coordinator)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    coordinator.movePointer(
                                        to: value.location,
                                        in: proxy.size
                                    )
                                }
                                .onEnded { _ in
                                    coordinator.endPointerInteraction()
                                }
                        )
                }
                .ignoresSafeArea()
            }

            readabilityScrim
            interfaceOverlay

            if !hasSeenSafetyIntroduction {
                SafetyIntroduction {
                    withAnimation(.easeOut(duration: 0.28)) {
                        hasSeenSafetyIntroduction = true
                    }
                    coordinator.recalibrate()
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            coordinator.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                coordinator.start()
                coordinator.recalibrate()
            case .inactive, .background:
                coordinator.pause()
            @unknown default:
                break
            }
        }
    }

    private var readabilityScrim: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.22), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 150)

            Spacer()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.18), location: 0.30),
                    .init(color: .black.opacity(0.66), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 300)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var interfaceOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                BrandMark()

                Spacer(minLength: 24)

                Button {
                    coordinator.recalibrate()
                } label: {
                    Label("校准", systemImage: "scope")
                }
                .buttonStyle(CalibrationButtonStyle())
                .accessibilityHint("把当前握持方向设为新的起始方向")
            }

            Spacer(minLength: 220)

            bottomHUD
        }
        .safeAreaPadding(.horizontal, 20)
        .safeAreaPadding(.top, 12)
        .safeAreaPadding(.bottom, 10)
    }

    private var bottomHUD: some View {
        VStack(spacing: 14) {
            speedReadout
                .frame(maxWidth: .infinity, alignment: .leading)

            instructionPanel
            statistics
        }
    }

    private var speedReadout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("当前转速")
                .font(.system(.caption2, design: .default, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
                .textCase(.uppercase)
                .tracking(1.1)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(coordinator.revolutionsPerSecond, format: .number.precision(.fractionLength(1)))
                    .font(.custom("Songti SC", size: 38, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.98, green: 0.83, blue: 0.56))
                    .contentTransition(.numericText())

                Text("圈/秒")
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "每秒转动 \(String(format: "%.1f", coordinator.revolutionsPerSecond)) 圈"
        )
    }

    private var instructionPanel: some View {
        HStack(spacing: 12) {
            OrbitInstructionGlyph(state: coordinator.interactionState)

            VStack(alignment: .leading, spacing: 3) {
                Text(instructionTitle)
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))

                Text(instructionDetail)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 62)
        .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(instructionTitle)，\(instructionDetail)")
    }

    private var instructionTitle: String {
        switch coordinator.interactionState {
        case .idle:
            "轻轻往复摇动手机"
        case .shaking:
            "已感应，继续摇动"
        case .spinning:
            "竹知了已经转起来了"
        case .touching:
            "正在用手指控制"
        case .automatic:
            "正在自动演示"
        case .unavailable:
            "按住屏幕滑动"
        }
    }

    private var instructionDetail: String {
        switch coordinator.interactionState {
        case .idle:
            "任意方向短幅连续摇动 · 也可按住屏幕滑动"
        case .shaking:
            "正在蓄力成圈 · 不需要大幅甩动"
        case .spinning:
            "持续摇动会转得更快、叫得更响"
        case .touching:
            "沿屏幕连续画圈 · 松手后恢复动作控制"
        case .automatic:
            "触摸屏幕后可切换为手指控制"
        case .unavailable:
            "动作传感器不可用 · 请沿屏幕连续画圈"
        }
    }

    private var statistics: some View {
        HStack(spacing: 0) {
            Statistic(label: "此刻在线", value: coordinator.stats.online)
            statisticDivider
            Statistic(label: "全球共鸣", value: coordinator.stats.wahs)
            statisticDivider
            Statistic(label: "我的哇声", value: coordinator.personalWahs)
        }
        .frame(maxWidth: .infinity)
        .contentTransition(.numericText())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "在线 \(coordinator.stats.online) 人，全球 \(coordinator.stats.wahs) 哇，我转出了 \(coordinator.personalWahs) 哇"
        )
    }

    private var statisticDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 0.5, height: 22)
    }
}

private struct BrandMark: View {
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("竹\n知\n了")
                .font(.custom("Songti SC", size: 34, relativeTo: .title))
                .lineSpacing(-4)
                .foregroundStyle(Color(red: 0.94, green: 0.89, blue: 0.78))
                .fixedSize()

            VStack(alignment: .leading, spacing: 9) {
                Text("童玩")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.68))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(
                        Color(red: 0.62, green: 0.10, blue: 0.055),
                        in: RoundedRectangle(cornerRadius: 3, style: .continuous)
                    )

                Text("一转\n就哇哇叫")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.60))
                    .lineSpacing(5)
                    .fixedSize()
            }
            .padding(.top, 3)
        }
        .shadow(color: .black.opacity(0.24), radius: 7, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("赛博竹知了，一转就哇哇叫")
    }
}

private struct Statistic: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(value, format: .number.notation(.compactName))
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.80))

            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OrbitInstructionGlyph: View {
    let state: ToyInteractionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0

    private var isActive: Bool {
        switch state {
        case .shaking, .spinning, .touching, .automatic:
            true
        case .idle, .unavailable:
            false
        }
    }

    private var accentColor: Color {
        switch state {
        case .spinning:
            Color(red: 1.0, green: 0.76, blue: 0.34)
        case .shaking, .touching, .automatic:
            Color(red: 0.96, green: 0.66, blue: 0.34)
        case .idle, .unavailable:
            .white.opacity(0.38)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 1)
                .frame(width: 28, height: 28)

            Circle()
                .trim(from: 0.06, to: 0.68)
                .stroke(
                    accentColor,
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
                .frame(width: 28, height: 28)

            Circle()
                .fill(Color(red: 0.72, green: 0.13, blue: 0.07))
                .frame(width: 6, height: 6)
                .offset(y: -14)
        }
        .rotationEffect(.degrees(rotation))
        .frame(width: 34, height: 34)
        .onAppear { updateAnimation() }
        .onChange(of: state) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        guard isActive, !reduceMotion else {
            rotation = 0
            return
        }
        rotation = 0
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

private struct SafetyIntroduction: View {
    let continueAction: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var orbitRotation = 0.0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.018, green: 0.026, blue: 0.070),
                    Color(red: 0.050, green: 0.058, blue: 0.112),
                    Color(red: 0.105, green: 0.078, blue: 0.105)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("赛博竹知了")
                        .font(.custom("Songti SC", size: 17, relativeTo: .headline))
                        .foregroundStyle(Color(red: 0.91, green: 0.85, blue: 0.73))
                    Spacer()
                    Text("安全提示")
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundStyle(.white.opacity(0.46))
                }

                Spacer()

                orbitIllustration

                Text("握稳手机，轻轻摇动")
                    .font(.custom("Songti SC", size: 31, relativeTo: .largeTitle))
                    .foregroundStyle(Color(red: 0.96, green: 0.91, blue: 0.82))
                    .padding(.top, 30)

                Text("任意方向短幅连续摇动，竹知了会自然摆动并逐渐转成圆圈。")
                    .font(.system(.body, design: .default))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                VStack(spacing: 15) {
                    SafetyStep(number: "01", text: "留出一臂的安全空间")
                    SafetyStep(number: "02", text: "单手握紧 iPhone，使用短幅动作")
                    SafetyStep(number: "03", text: "连续轻摇即可，不需要大力挥动")
                }
                .padding(.top, 30)

                Spacer()

                Text("稳定起转与每完成一圈，都有触感反馈")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(.white.opacity(0.44))
                    .padding(.bottom, 14)

                Button("我已握稳", action: continueAction)
                    .buttonStyle(PrimaryActionButtonStyle())
            }
            .safeAreaPadding(.horizontal, 26)
            .safeAreaPadding(.top, 16)
            .safeAreaPadding(.bottom, 12)
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) {
                orbitRotation = 360
            }
        }
    }

    private var orbitIllustration: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 1)
                .frame(width: 162, height: 162)

            Circle()
                .trim(from: 0.04, to: 0.78)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.93, green: 0.69, blue: 0.38),
                            Color(red: 0.59, green: 0.10, blue: 0.055)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 162, height: 162)

            Circle()
                .fill(Color(red: 0.70, green: 0.12, blue: 0.065))
                .frame(width: 12, height: 12)
                .offset(y: -81)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(red: 0.14, green: 0.14, blue: 0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.32), lineWidth: 1)
                }
                .frame(width: 38, height: 72)
                .rotationEffect(.degrees(14))
        }
        .rotationEffect(.degrees(orbitRotation))
        .accessibilityHidden(true)
    }
}

private struct SafetyStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Text(number)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(Color(red: 0.94, green: 0.61, blue: 0.33))
                .frame(width: 28, alignment: .leading)

            Text(text)
                .font(.system(.subheadline, design: .default, weight: .medium))
                .foregroundStyle(.white.opacity(0.80))

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct CalibrationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .default, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.56 : 0.82))
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .background(Color.black.opacity(configuration.isPressed ? 0.34 : 0.23), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.14), lineWidth: 0.75)
            }
            .contentShape(Capsule())
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .default, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.72 : 0.96))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                Color(red: 0.64, green: 0.095, blue: 0.045)
                    .opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 0.96, green: 0.47, blue: 0.27).opacity(0.48), lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
