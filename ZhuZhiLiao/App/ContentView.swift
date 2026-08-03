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
                MetalSurface(coordinator: coordinator)
                    .ignoresSafeArea()
            }

            interfaceOverlay

            if !hasSeenSafetyIntroduction {
                SafetyIntroduction {
                    hasSeenSafetyIntroduction = true
                    coordinator.recalibrate()
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
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

    private var interfaceOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                titleBlock
                Spacer()
                Text("儿\n时\n玩\n物")
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.62))
                    .lineSpacing(2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.72, green: 0.20, blue: 0.10).opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityHidden(true)
                Spacer(minLength: 42)
                Button("重新校准") {
                    coordinator.recalibrate()
                }
                .buttonStyle(InkCapsuleButtonStyle())
                .accessibilityHint("把当前握持方向设为新的起始方向")
            }

            Spacer()

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("竹膜为鼓　松香为弦")
                    Text("摩擦生振　膜腔共鸣")
                }
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(.white.opacity(0.42))

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    speedReadout
                    Button(coordinator.automaticMode ? "停一停" : "自动甩") {
                        coordinator.toggleAutomaticMode()
                    }
                    .buttonStyle(GlowButtonStyle(isActive: coordinator.automaticMode))
                    .accessibilityHint("不摇手机也能演示竹知了转动")
                }
            }

            instructionPill
                .padding(.top, 10)

            statsLine
                .padding(.top, 13)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: -4) {
                ForEach(Array("竹知了"), id: \.self) { character in
                    Text(String(character))
                        .font(.custom("Songti SC", size: 43))
                        .foregroundStyle(Color(red: 0.96, green: 0.92, blue: 0.83))
                }
            }
            Text("一\n转\n，\n就\n哇\n哇\n地\n叫")
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(1)
                .padding(.top, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("竹知了，一转就哇哇地叫")
    }

    private var speedReadout: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(coordinator.revolutionsPerSecond, format: .number.precision(.fractionLength(1)))
                .font(.custom("Songti SC", size: 30))
                .monospacedDigit()
                .foregroundStyle(Color(red: 1.0, green: 0.87, blue: 0.64))
            Text("圈 / 秒")
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(.white.opacity(0.55))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "每秒转动 \(String(format: "%.1f", coordinator.revolutionsPerSecond)) 圈"
        )
    }

    private var instructionPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "gyroscope")
                .rotationEffect(.degrees(coordinator.isRunning ? 22 : 0))
                .animation(.easeInOut(duration: 0.5), value: coordinator.isRunning)
            Text(coordinator.motionIsAvailable ? "握稳手机　用手腕画小圈" : "当前设备无动作传感器　可使用自动甩")
        }
        .font(.system(size: 13, weight: .medium, design: .serif))
        .foregroundStyle(.white.opacity(0.86))
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(.black.opacity(0.34), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.09), lineWidth: 1))
        .frame(maxWidth: .infinity)
        .accessibilityLabel(coordinator.motionIsAvailable ? "握稳手机，用手腕画小圈" : "动作传感器不可用，请使用自动甩")
    }

    private var statsLine: some View {
        Text("此刻 \(coordinator.stats.online) 人 · 来客 \(coordinator.stats.visitors) · 访问 \(coordinator.stats.visits) · 全球 \(coordinator.stats.wahs) 哇 · 我 \(coordinator.personalWahs) 哇")
            .font(.system(size: 9, design: .serif))
            .foregroundStyle(.white.opacity(0.45))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity)
            .contentTransition(.numericText())
            .accessibilityLabel("全球统计：在线 \(coordinator.stats.online) 人，我转出了 \(coordinator.personalWahs) 哇")
    }
}

private struct SafetyIntroduction: View {
    let continueAction: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.09).opacity(0.96)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color(red: 0.95, green: 0.53, blue: 0.30))

                Text("握稳手机")
                    .font(.custom("Songti SC", size: 30))

                Text("请留出安全空间，用手腕轻轻画小圈。\n不需要大力挥动，也不要松开手机。")
                    .font(.system(size: 15, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(6)

                Button("开始体验", action: continueAction)
                    .buttonStyle(GlowButtonStyle(isActive: true))
            }
            .padding(32)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct InkCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, design: .serif))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.5 : 0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.2), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
    }
}

private struct GlowButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium, design: .serif))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.65 : 0.95))
            .frame(minWidth: 92)
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(
                isActive
                    ? Color(red: 0.91, green: 0.29, blue: 0.15).opacity(0.92)
                    : Color.black.opacity(0.26),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    Color(red: 1, green: 0.45, blue: 0.28).opacity(isActive ? 0.6 : 0.35),
                    lineWidth: 1
                )
            )
            .shadow(color: Color.orange.opacity(isActive ? 0.28 : 0), radius: 15)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
