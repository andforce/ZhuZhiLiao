import SwiftUI

@main
struct ZhuZhiLiaoApp: App {
    @StateObject private var coordinator = ExperienceCoordinator()
    @State private var themeStore = SeasonThemeStore()

    var body: some Scene {
        WindowGroup {
            ContentView(coordinator: coordinator)
                .environment(themeStore)
        }
    }
}
