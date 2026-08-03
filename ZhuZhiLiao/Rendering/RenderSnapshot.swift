import simd

struct RenderSnapshot: Equatable, Sendable {
    var state: ToyPhysicsState
    var revolutionsPerSecond: Float
    var phase: Float
    var elapsedTime: Float
    var rotationRate: SIMD3<Float>
    var emittedWahs: Int
}

