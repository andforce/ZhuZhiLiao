@preconcurrency import CoreMotion
import Foundation
import simd

struct MotionSample: Equatable, Sendable {
    var userAcceleration: SIMD3<Float>
    var gravityDirection: SIMD3<Float>
    var rotationRate: SIMD3<Float>
    var relativeAttitude: simd_quatf
    var shakeDrive: ShakeDrive
    var timestamp: TimeInterval
    var isAvailable: Bool

    static let unavailable = MotionSample(
        userAcceleration: .zero,
        gravityDirection: SIMD3<Float>(0, -1, 0),
        rotationRate: .zero,
        relativeAttitude: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
        shakeDrive: .inactive,
        timestamp: 0,
        isAvailable: false
    )
}

@MainActor
final class MotionController {
    private let manager = CMMotionManager()
    private let processor = MotionSampleProcessor()
    private let processingQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.azhegezhege.zhuzhiliao.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()

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

        processor.beginSession()
        manager.deviceMotionUpdateInterval = 1.0 / 100.0
        manager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: processingQueue,
            withHandler: processor.makeDeviceMotionHandler()
        )
        isRunning = true
    }

    func stop() {
        isRunning = false
        manager.stopDeviceMotionUpdates()
        processor.endSession()
    }

    func resetCalibration() {
        processor.resetCalibration()
    }

    func resetGestureState(preservingDirection: Bool = true) {
        processor.resetGestureState(preservingDirection: preservingDirection)
    }

    func latestSample() -> MotionSample {
        guard isRunning else {
            return .unavailable
        }
        return processor.latestSample()
    }
}

/// Core Motion 的回调与渲染循环位于不同线程；所有可变滤波状态都在这个
/// 小型锁保护对象中处理，主线程只读取完整快照，不会看见半更新的数据。
private final class MotionSampleProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var acceptsSamples = false
    private var referenceAttitude: simd_quatf?
    private var accelerationFilter = MotionSampleFilter()
    private var shakeDetector = ShakeGestureDetector()
    private var sample = MotionSample.unavailable

    /// 在非 MainActor 类型的上下文中创建 Core Motion 回调，避免闭包继承
    /// `MotionController.start()` 的主线程隔离后在专用队列上触发运行时断言。
    func makeDeviceMotionHandler() -> CMDeviceMotionHandler {
        { [weak self] motion, _ in
            guard let self, let motion else { return }
            process(motion)
        }
    }

    func beginSession() {
        lock.withLock {
            acceptsSamples = true
            resetCalibrationLocked()
        }
    }

    func endSession() {
        lock.withLock {
            acceptsSamples = false
            resetCalibrationLocked()
        }
    }

    func resetCalibration() {
        lock.withLock {
            resetCalibrationLocked()
        }
    }

    func resetGestureState(preservingDirection: Bool) {
        lock.withLock {
            sample.shakeDrive = shakeDetector.reset(
                preservingOrbitAxis: preservingDirection
            )
        }
    }

    func latestSample() -> MotionSample {
        lock.withLock {
            guard sample.isAvailable,
                  ProcessInfo.processInfo.systemUptime - sample.timestamp > 0.15 else {
                return sample
            }

            var staleSample = sample
            staleSample.userAcceleration = .zero
            staleSample.rotationRate = .zero
            staleSample.shakeDrive = .inactive(
                orbitAxis: sample.shakeDrive.orbitAxis
            )
            return staleSample
        }
    }

    func process(_ motion: CMDeviceMotion) {
        lock.withLock {
            guard acceptsSamples else { return }

            let attitude = motion.attitude.quaternion.simdQuaternion
            if referenceAttitude == nil {
                referenceAttitude = attitude
            }
            guard let referenceAttitude else { return }

            // Core Motion 的向量位于当前设备坐标。先回到参考坐标，再旋转到
            // 启动时的屏幕坐标，使 x/y/z 始终表示首帧的右/上/出屏方向。
            let deviceToCalibratedScene = simd_normalize(referenceAttitude * attitude.inverse)
            let measuredAcceleration = deviceToCalibratedScene.act(
                motion.userAcceleration.simdVector
            )
            let gravity = deviceToCalibratedScene.act(motion.gravity.simdVector)
            let rotationRate = deviceToCalibratedScene.act(motion.rotationRate.simdVector)
            let filteredAcceleration = accelerationFilter.process(
                measuredAcceleration,
                timestamp: motion.timestamp
            )
            let shakeDrive = shakeDetector.process(
                acceleration: measuredAcceleration,
                rotationRate: rotationRate,
                timestamp: motion.timestamp
            )

            sample = MotionSample(
                userAcceleration: filteredAcceleration,
                gravityDirection: gravity,
                rotationRate: rotationRate,
                relativeAttitude: deviceToCalibratedScene,
                shakeDrive: shakeDrive,
                timestamp: motion.timestamp,
                isAvailable: true
            )
        }
    }

    private func resetCalibrationLocked() {
        referenceAttitude = nil
        accelerationFilter.reset()
        shakeDetector.reset()
        sample = .unavailable
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
