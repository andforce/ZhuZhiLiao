import MetalKit
import SwiftUI

struct MetalSurface: UIViewRepresentable {
    let coordinator: ExperienceCoordinator
    let theme: SeasonTheme
    let animateThemeChanges: Bool

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(coordinator: coordinator, theme: theme)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        context.coordinator.configure(view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.setTheme(theme, animated: animateThemeChanges)
        if view.delegate == nil {
            context.coordinator.configure(view)
        }
    }

    static func dismantleUIView(_ view: MTKView, coordinator: MetalRenderer) {
        view.isPaused = true
        view.delegate = nil
    }
}
