import MetalKit
import SwiftUI

struct EarthMetalSurface: UIViewRepresentable {
    let nodes: [EarthNode]
    let serverClockOffsetMilliseconds: Int64
    let localWahAt: Date?
    let reduceMotion: Bool
    let onDetailChange: (Int) -> Void
    let onSelect: (EarthNode?) -> Void

    func makeCoordinator() -> EarthMetalRenderer {
        EarthMetalRenderer(
            onDetailChange: onDetailChange,
            onSelect: onSelect
        )
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        context.coordinator.configure(view)
        context.coordinator.update(
            nodes: nodes,
            serverClockOffsetMilliseconds: serverClockOffsetMilliseconds,
            localWahAt: localWahAt,
            reduceMotion: reduceMotion,
            onDetailChange: onDetailChange,
            onSelect: onSelect
        )
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(
            nodes: nodes,
            serverClockOffsetMilliseconds: serverClockOffsetMilliseconds,
            localWahAt: localWahAt,
            reduceMotion: reduceMotion,
            onDetailChange: onDetailChange,
            onSelect: onSelect
        )
        if view.delegate == nil {
            context.coordinator.configure(view)
        }
    }

    static func dismantleUIView(_ view: MTKView, coordinator: EarthMetalRenderer) {
        view.isPaused = true
        view.delegate = nil
        view.gestureRecognizers?.forEach(view.removeGestureRecognizer)
    }
}
