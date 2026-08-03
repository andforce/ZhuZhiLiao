@preconcurrency import CoreMotion
import simd

struct MotionSample: Equatable, Sendable {
    var userAcceleration: SIMD3<Float>
    var gravityDirection: SIMD3<Float>
    var rotationRate: SIMD3<Float>
    var relativeAttitude: simd_quatf
    var timestamp: TimeInterval
    var isAvailable: Bool

    static let unavailable = MotionSample(
        userAcceleration: .zero,
        gravityDirection: SIMD3<Float>(0, -1, 0),
        rotationRate: .zero,
        relativeAttitude: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
        timestamp: 0,
        isAvailable: false
    )
}

@MainActor
final class MotionController {
    private let manager = CMMotionManager()
    private var referenceAttitude: simd_quatf?
    private var accelerationFilter = MotionSampleFilter()
    private var elbowPivotFilter = ElbowPivotMotionFilter()

    private(set) var isRunning = false

    var isAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    func start() {
        guard manager.isDeviceMotionAvailable else {
            isRunning = false
            return
        }
        guard !isRunning else { return }

        manager.deviceMotionUpdateInterval = 1.0 / 100.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        isRunning = true
        resetCalibration()
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        isRunning = false
        resetCalibration()
    }

    func resetCalibration() {
        referenceAttitude = nil
        accelerationFilter.reset()
        elbowPivotFilter.reset()
    }

    func latestSample() -> MotionSample {
        guard isRunning, let motion = manager.deviceMotion else {
            return .unavailable
        }

        let attitude = motion.attitude.quaternion.simdQuaternion
        if referenceAttitude == nil {
            referenceAttitude = attitude
        }
        guard let referenceAttitude else { return .unavailable }

        // Core Motion 的向量位于当前设备坐标。先回到参考坐标，再旋转到
        // 启动时的屏幕坐标，使 x/y/z 始终表示首帧的右/上/出屏方向。
        let deviceToCalibratedScene = simd_normalize(referenceAttitude * attitude.inverse)
        let measuredAcceleration = deviceToCalibratedScene.act(motion.userAcceleration.simdVector)
        let gravity = deviceToCalibratedScene.act(motion.gravity.simdVector)
        let rotationRate = deviceToCalibratedScene.act(motion.rotationRate.simdVector)
        let pivotToPhoneDirection = deviceToCalibratedScene.act(SIMD3<Float>(0, 1, 0))
        let filteredAcceleration = accelerationFilter.process(
            measuredAcceleration,
            timestamp: motion.timestamp
        )
        let assistedAcceleration = elbowPivotFilter.process(
            measuredAcceleration: filteredAcceleration,
            rotationRate: rotationRate,
            pivotToPhoneDirection: pivotToPhoneDirection,
            timestamp: motion.timestamp
        )

        return MotionSample(
            userAcceleration: assistedAcceleration,
            gravityDirection: gravity,
            rotationRate: rotationRate,
            relativeAttitude: deviceToCalibratedScene,
            timestamp: motion.timestamp,
            isAvailable: true
        )
    }
}

private extension CMAcceleration {
    var simdVector: SIMD3<Float> {
        SIMD3<Float>(Float(x), Float(y), Float(z))
    }
}

private extension CMRotationRate {
    var simdVector: SIMD3<Float> {
        SIMD3<Float>(Float(x), Float(y), Float(z))
    }
}

private extension CMQuaternion {
    var simdQuaternion: simd_quatf {
        simd_normalize(simd_quatf(ix: Float(x), iy: Float(y), iz: Float(z), r: Float(w)))
    }
}
