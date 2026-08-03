import simd

struct MotionFilterConfiguration: Equatable, Sendable {
    var deadZone: Float
    var maximumMagnitude: Float
    var smoothingFactor: Float

    static let live = MotionFilterConfiguration(
        deadZone: 0.03,
        maximumMagnitude: 2.5,
        smoothingFactor: 0.25
    )
}

struct MotionSampleFilter: Sendable {
    let configuration: MotionFilterConfiguration
    private(set) var filteredValue = SIMD3<Float>.zero

    init(configuration: MotionFilterConfiguration = .live) {
        self.configuration = configuration
    }

    mutating func process(_ sample: SIMD3<Float>) -> SIMD3<Float> {
        let magnitude = simd_length(sample)
        let target: SIMD3<Float>

        if magnitude < configuration.deadZone {
            target = .zero
        } else if magnitude > configuration.maximumMagnitude, magnitude > 0 {
            target = sample * (configuration.maximumMagnitude / magnitude)
        } else {
            target = sample
        }

        let smoothing = min(max(configuration.smoothingFactor, 0), 1)
        filteredValue += (target - filteredValue) * smoothing
        return filteredValue
    }

    mutating func reset() {
        filteredValue = .zero
    }
}

