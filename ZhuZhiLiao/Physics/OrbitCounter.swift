import simd

struct OrbitCounter: Sendable {
    private var accumulatedAngle: Float = 0
    private var stableAxis: SIMD3<Float>?

    mutating func reset() {
        accumulatedAngle = 0
        stableAxis = nil
    }

    mutating func update(
        angleDelta: Float,
        axis: SIMD3<Float>,
        isQualified: Bool
    ) -> Int {
        let axisMagnitude = simd_length(axis)
        guard isQualified, angleDelta > 0, axisMagnitude > 0.000_001 else {
            reset()
            return 0
        }

        let measuredAxis = axis / axisMagnitude
        if let previousAxis = stableAxis {
            guard simd_dot(previousAxis, measuredAxis) >= 0.75 else {
                accumulatedAngle = 0
                stableAxis = measuredAxis
                return 0
            }
            stableAxis = simd_normalize(previousAxis * 0.9 + measuredAxis * 0.1)
        } else {
            stableAxis = measuredAxis
        }

        accumulatedAngle += angleDelta
        guard accumulatedAngle >= 2 * .pi else { return 0 }

        let completed = Int(accumulatedAngle / (2 * .pi))
        accumulatedAngle.formTruncatingRemainder(dividingBy: 2 * .pi)
        return completed
    }
}
