import SwiftUI

struct ContentView: View {
    @Environment(SeasonThemeStore.self) private var themeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var coordinator: ExperienceCoordinator
    @AppStorage("zzl_safety_intro_seen") private var hasSeenSafetyIntroduction = false
    @State private var presentedSheet: AppSheet?
    @State private var presentedCover: AppCover?

    private let isRunningUnitTests = ProcessInfo.processInfo.environment[
        "XCTestConfigurationFilePath"
    ] != nil

    var body: some View {
        ZStack {
            SeasonalScene(
                coordinator: coordinator,
                theme: themeStore.selectedTheme,
                reduceMotion: reduceMotion,
                isRunningUnitTests: isRunningUnitTests
            )

            SeasonalReadabilityScrim(theme: themeStore.selectedTheme)
            ExperienceHUD(
                coordinator: coordinator,
                theme: themeStore.selectedTheme,
                showThemePicker: showThemePicker,
                showEarth: showEarth,
                showLeaderboard: showLeaderboard
            )

            if !hasSeenSafetyIntroduction {
                SafetyIntroduction(theme: themeStore.selectedTheme, continueAction: finishSafetyIntroduction)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .themePicker:
                ThemePickerView(themeStore: themeStore)
            case .leaderboard:
                LeaderboardView(
                    coordinator: coordinator,
                    theme: themeStore.selectedTheme
                )
            }
        }
        .fullScreenCover(item: $presentedCover) { cover in
            switch cover {
            case .earth:
                WahEarthView(
                    coordinator: coordinator,
                    theme: themeStore.selectedTheme
                )
            }
        }
        .onAppear(perform: coordinator.start)
        .onChange(of: scenePhase, handleScenePhaseChange)
    }

    private func showThemePicker() {
        presentedSheet = .themePicker
    }

    private func showLeaderboard() {
        presentedSheet = .leaderboard
    }

    private func showEarth() {
        presentedCover = .earth
    }

    private func finishSafetyIntroduction() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) {
            hasSeenSafetyIntroduction = true
        }
        coordinator.recalibrate()
    }

    private func handleScenePhaseChange(_ oldValue: ScenePhase, _ phase: ScenePhase) {
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

private enum AppSheet: String, Identifiable {
    case themePicker
    case leaderboard

    var id: String { rawValue }
}

private enum AppCover: String, Identifiable {
    case earth
    var id: String { rawValue }
}

private struct SeasonalScene: View {
    let coordinator: ExperienceCoordinator
    let theme: SeasonTheme
    let reduceMotion: Bool
    let isRunningUnitTests: Bool

    var body: some View {
        GeometryReader { proxy in
            MetalSurface(
                coordinator: coordinator,
                theme: theme,
                animateThemeChanges: !reduceMotion
            )
            .opacity(isRunningUnitTests ? 0 : 1)
            .contentShape(Rectangle())
            .gesture(pointerGesture(in: proxy.size))
        }
        .background(theme.colors.skyTop)
        .ignoresSafeArea()
        .allowsHitTesting(!isRunningUnitTests)
    }

    private func pointerGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                coordinator.movePointer(to: value.location, in: size)
            }
            .onEnded { _ in
                coordinator.endPointerInteraction()
            }
    }
}

private struct SeasonalReadabilityScrim: View {
    let theme: SeasonTheme

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [theme.colors.skyTop.opacity(0.58), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 168)

            Spacer()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: theme.colors.panel.opacity(0.28), location: 0.30),
                    .init(color: .black.opacity(0.76), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 340)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#Preview("夏 · 主界面") {
    ContentView(coordinator: ExperienceCoordinator())
        .environment(SeasonThemeStore(date: Date(timeIntervalSince1970: 1_720_000_000)))
}
