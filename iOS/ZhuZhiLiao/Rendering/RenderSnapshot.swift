import simd

/// Metal 相机、初始锚点与触摸反投影共用同一组场景尺度。
/// 纵向可见范围按 iPhone 小屏网页的 `ROPE_LEN = minDim * 0.28` 校准，
/// 防止高速甩动时竹知了越出画面。
enum ToySceneLayout {
    static let cameraEye = SIMD3<Float>(0, 0.10, 16.0)
    static let cameraTarget = SIMD3<Float>(0, -0.15, 0)
    static let fieldOfViewY: Float = 42 * .pi / 180
    static let visibleHeightAtToyPlane: Float = 12.28
    static let initialAnchor = SIMD3<Float>(0.24, 0.72, 0)
}

struct RenderSnapshot: Equatable, Sendable {
    var state: ToyPhysicsState
    var revolutionsPerSecond: Float
    var phase: Float
    var elapsedTime: Float
    var rotationRate: SIMD3<Float>
    var emittedWahs: Int
}
