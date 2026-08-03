import SwiftUI

@main
struct ZhuZhiLiaoApp: App {
    @StateObject private var coordinator = ExperienceCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView(coordinator: coordinator)
        }
    }
}
