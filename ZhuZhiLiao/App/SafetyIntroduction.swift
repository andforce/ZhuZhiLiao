import SwiftUI

struct SafetyIntroduction: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let theme: SeasonTheme
    let continueAction: () -> Void
    @State private var orbitRotation = 0.0

    var body: some View {
        ZStack {
            SafetyBackground(theme: theme)

            VStack(spacing: 0) {
                HStack {
                    Text("赛博竹知了")
                        .font(.custom("Songti SC", size: 18, relativeTo: .headline))
                        .foregroundStyle(.white.opacity(0.92))

                    Spacer()

                    Label(theme.displayName + " · 安全提示", systemImage: theme.symbolName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.colors.highlight.opacity(0.82))
                }

                Spacer(minLength: 22)

                SafetyOrbitIllustration(
                    theme: theme,
                    rotation: orbitRotation
                )

                Text("握稳手机，轻轻摇动")
                    .font(.custom("Songti SC", size: 31, relativeTo: .largeTitle))
                    .foregroundStyle(.white.opacity(0.96))
                    .multilineTextAlignment(.center)
                    .padding(.top, 26)

                Text("任意方向短幅连续摇动，竹知了会自然摆动并逐渐转成圆圈。")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.64))
                    .multilineTextAlignment(.center)
                    .padding(.top, 9)

                VStack(spacing: 14) {
                    SafetyStep(number: "01", text: "留出一臂的安全空间", theme: theme)
                    SafetyStep(number: "02", text: "单手握紧 iPhone，使用短幅动作", theme: theme)
                    SafetyStep(number: "03", text: "连续轻摇即可，不需要大力挥动", theme: theme)
                }
                .padding(16)
                .seasonalGlass(theme: theme, cornerRadius: 22)
                .padding(.top, 26)

                Spacer(minLength: 18)

                Text("稳定起转与每完成一圈，都有触感反馈")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
                    .padding(.bottom, 13)

                SafetyContinueButton(theme: theme, action: continueAction)
            }
            .safeAreaPadding(.horizontal, 24)
            .safeAreaPadding(.top, 15)
            .safeAreaPadding(.bottom, 12)
        }
        .accessibilityElement(children: .contain)
        .onAppear(perform: startOrbitAnimation)
    }

    private func startOrbitAnimation() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) {
            orbitRotation = 360
        }
    }
}

private struct SafetyBackground: View {
    let theme: SeasonTheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.colors.skyTop, theme.colors.skyBottom, .black],
                startPoint: .top,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(theme.colors.accent.opacity(0.17))
                .frame(width: 310, height: 310)
                .blur(radius: 70)
                .offset(x: 150, y: -260)

            Circle()
                .fill(theme.colors.secondaryAccent.opacity(0.18))
                .frame(width: 350, height: 350)
                .blur(radius: 85)
                .offset(x: -170, y: 300)
        }
        .ignoresSafeArea()
    }
}

private struct SafetyOrbitIllustration: View {
    let theme: SeasonTheme
    let rotation: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.10), lineWidth: 1)

            Circle()
                .trim(from: 0.04, to: 0.79)
                .stroke(
                    LinearGradient(
                        colors: [theme.colors.highlight, theme.colors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )

            Circle()
                .fill(theme.colors.accent)
                .frame(width: 12, height: 12)
                .offset(y: -80)

            Image(systemName: theme.symbolName)
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(theme.colors.highlight)
                .shadow(color: theme.colors.accent.opacity(0.55), radius: 14)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.black.opacity(0.54))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.30), lineWidth: 1)
                }
                .frame(width: 37, height: 70)
                .rotationEffect(.degrees(14))
        }
        .frame(width: 160, height: 160)
        .rotationEffect(.degrees(rotation))
        .accessibilityHidden(true)
    }
}

private struct SafetyStep: View {
    let number: String
    let text: String
    let theme: SeasonTheme

    var body: some View {
        HStack(spacing: 14) {
            Text(number)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 28, alignment: .leading)

            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.84))

            Spacer(minLength: 0)
        }
    }
}

private struct SafetyContinueButton: View {
    let theme: SeasonTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("我已握稳")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            theme.colors.accent.opacity(0.76),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .seasonalGlass(theme: theme, cornerRadius: 18, interactive: true)
    }
}

#Preview("春 · 安全引导") {
    SafetyIntroduction(theme: .spring, continueAction: {})
}
