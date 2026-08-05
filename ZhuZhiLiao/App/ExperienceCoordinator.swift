import Combine
import Foundation
import UIKit

enum ToyInteractionState: Equatable, Sendable {
    case idle
    case shaking
    case spinning
    case touching
    case automatic
    case unavailable
}

@MainActor
final class ExperienceCoordinator: ObservableObject {
    @Published private(set) var revolutionsPerSecond: Float = 0
    @Published private(set) var activity: Float = 0
    @Published private(set) var stats = CounterStats(online: 0, wahs: 0)
    @Published private(set) var personalWahs = 0
    @Published private(set) var motionIsAvailable = false
    @Published private(set) var isRunning = false
    @Published private(set) var interactionState: ToyInteractionState = .idle
    @Published private(set) var leaderboardCode: String?
    @Published private(set) var earthIsEnabled = false
    @Published private(set) var earthCellID: String?
    @Published private(set) var earthRevision = 0
    @Published private(set) var lastLocalWahAt: Date?
    @Published private(set) var earthIsPresented = false
    private var automaticMode = false

    private let motionController: MotionController
    private let audioEngine: ToyAudioEngine
    private let counterService: CounterService
    private let hapticFeedback = ToyHapticFeedback()
    private var simulation: ToySimulation
    private var simulationTask: Task<Void, Never>?
    private var latestSimulationFrame: SimulationFrame
    private var latestRotationRate = SIMD3<Float>.zero
    private var pendingRenderedWahs = 0
    private var awaitingCalibratedGravity = true
    private var lastHUDPresentationTime: CFTimeInterval = 0
    private var elapsedTime: Float = 0
    private var automaticPhase: Float = 0
    private var automaticRPS: Float = 0
    private var pointerAnchorTarget: SIMD3<Float>?
    private var pointerIsActive = false
    private var hasUsedPointerFallback = false
    private var latestShakeDrive = ShakeDrive.inactive
    private let isRunningUnitTests: Bool

    init(
        motionController: MotionController = MotionController(),
        audioEngine: ToyAudioEngine = ToyAudioEngine(),
        counterService: CounterService = CounterService(),
        simulation: ToySimulation = ToySimulation()
    ) {
        self.motionController = motionController
        self.audioEngine = audioEngine
        self.counterService = counterService
        self.simulation = simulation
        latestSimulationFrame = SimulationFrame(
            state: simulation.state,
            revolutionsPerSecond: 0,
            phase: 0,
            completedWahs: 0
        )
        isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        leaderboardCode = counterService.publicCode
        earthIsEnabled = counterService.earthIsEnabled
        earthCellID = counterService.earthCellID
        counterService.earthRevisionHandler = { [weak self] revision in
            self?.earthRevision = revision
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        motionController.start()
        motionIsAvailable = motionController.isAvailable

        automaticMode = !motionIsAvailable && !hasUsedPointerFallback
        interactionState = automaticMode
            ? .automatic
            : (motionIsAvailable ? .idle : .unavailable)

        guard !isRunningUnitTests else { return }
        startSimulationLoop()
        audioEngine.start()
        hapticFeedback.prepare()
        counterService.start()
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        simulationTask?.cancel()
        simulationTask = nil
        motionController.stop()

        guard !isRunningUnitTests else { return }
        audioEngine.pause()
        hapticFeedback.reset()
        counterService.stop()
    }

    func recalibrate() {
        pointerAnchorTarget = .zero
        pointerIsActive = false
        latestShakeDrive = .inactive
        motionController.resetCalibration()
        if automaticMode || !motionIsAvailable {
            resetSimulation(gravityDirection: SIMD3<Float>(0, -1, 0))
            awaitingCalibratedGravity = false
        } else {
            awaitingCalibratedGravity = true
        }
        interactionState = automaticMode
            ? .automatic
            : (motionIsAvailable ? .idle : .unavailable)
    }

    /// 把 SwiftUI 触点换算到与 Metal 场景 z=0 平面相同的世界坐标。
    /// 这使 iOS 上的手指/模拟器鼠标与网页版 pointer target 语义一致。
    func movePointer(to location: CGPoint, in viewport: CGSize) {
        guard viewport.width > 0, viewport.height > 0 else { return }

        if !pointerIsActive {
            motionController.resetGestureState(preservingDirection: true)
            latestShakeDrive = .inactive
        }

        let visibleHeight = ToySceneLayout.visibleHeightAtToyPlane
        let visibleWidth = visibleHeight * Float(viewport.width / viewport.height)
        let normalizedX = Float(location.x / viewport.width) - 0.5
        let normalizedY = 0.5 - Float(location.y / viewport.height)
        let worldPoint = SIMD3<Float>(
            normalizedX * visibleWidth,
            ToySceneLayout.cameraTarget.y + normalizedY * visibleHeight,
            0
        )
        pointerAnchorTarget = worldPoint - ToySceneLayout.initialAnchor
        pointerIsActive = true
        hasUsedPointerFallback = true
        automaticMode = false
        interactionState = .touching
    }

    func endPointerInteraction() {
        pointerIsActive = false
        pointerAnchorTarget = .zero
        latestShakeDrive = .inactive
        motionController.resetGestureState(preservingDirection: true)
        interactionState = motionIsAvailable ? .idle : .unavailable
    }

    func frame(at timestamp: CFTimeInterval) -> RenderSnapshot {
        let frame = latestSimulationFrame
        let emittedWahs = pendingRenderedWahs
        pendingRenderedWahs = 0

        if !isRunningUnitTests {
            audioEngine.update(
                revolutionsPerSecond: frame.revolutionsPerSecond,
                activity: frame.state.activity,
                phase: frame.phase
            )
        }

        if timestamp - lastHUDPresentationTime >= 0.12 {
            lastHUDPresentationTime = timestamp
            revolutionsPerSecond = frame.revolutionsPerSecond
            activity = frame.state.activity
            stats = counterService.stats
            personalWahs = counterService.personalWahs
            leaderboardCode = counterService.publicCode
            earthIsEnabled = counterService.earthIsEnabled
            earthCellID = counterService.earthCellID
            interactionState = resolvedInteractionState(for: frame)
        }

        return RenderSnapshot(
            state: frame.state,
            revolutionsPerSecond: frame.revolutionsPerSecond,
            phase: frame.phase,
            elapsedTime: elapsedTime,
            rotationRate: latestRotationRate,
            emittedWahs: emittedWahs
        )
    }

    func loadLeaderboard() async throws -> LeaderboardSnapshot {
        try await counterService.loadLeaderboard()
    }

    func resetAnonymousIdentity() async throws {
        try await counterService.resetAnonymousIdentity()
        leaderboardCode = counterService.publicCode
        personalWahs = counterService.personalWahs
        earthIsEnabled = counterService.earthIsEnabled
        earthCellID = counterService.earthCellID
    }

    func setEarthLocation(cellID: String) async throws {
        try await counterService.setEarthLocation(cellID: cellID)
        earthIsEnabled = counterService.earthIsEnabled
        earthCellID = counterService.earthCellID
    }

    func disableEarth() async throws {
        try await counterService.disableEarth()
        earthIsEnabled = false
        earthCellID = nil
    }

    func loadEarthSnapshot(
        detail: Int,
        bounds: [EarthBounds] = []
    ) async throws -> EarthSnapshot {
        try await counterService.loadEarthSnapshot(detail: detail, bounds: bounds)
    }

    func setEarthPresented(_ isPresented: Bool) {
        earthIsPresented = isPresented
    }

    private func startSimulationLoop() {
        simulationTask?.cancel()
        simulationTask = Task { @MainActor [weak self] in
            var previousTime = CACurrentMediaTime()
            while let self, !Task.isCancelled, self.isRunning {
                let currentTime = CACurrentMediaTime()
                self.stepSimulation(deltaTime: currentTime - previousTime)
                previousTime = currentTime
                try? await Task.sleep(for: .nanoseconds(8_333_333))
            }
        }
    }

    private func stepSimulation(deltaTime: TimeInterval) {
        let clampedDeltaTime = min(max(deltaTime, 0), 0.05)
        let input: MotionInput
        if pointerIsActive, let pointerAnchorTarget {
            input = MotionInput(
                anchorAcceleration: .zero,
                gravityDirection: SIMD3<Float>(0, -1, 0),
                rotationRate: .zero,
                anchorTarget: pointerAnchorTarget
            )
            latestRotationRate = .zero
            latestShakeDrive = .inactive
        } else if automaticMode {
            // 网页“自动甩”的同款输入：转速缓入到 3.4 圈/秒，杆梢沿
            // iPhone 小屏使用网页响应式比例 0.13/0.28，由模拟器内部再做
            // 26/s 平滑；桌面网页达到上限后才会收敛到 58/150。
            let delta = Float(clampedDeltaTime)
            automaticRPS += (3.4 - automaticRPS) * min(1, delta * 1.1)
            automaticPhase += automaticRPS * delta * 2 * .pi
            let radius = simulation.state.ropeLength * (Float(13) / Float(28))
            let target = SIMD3<Float>(
                cos(automaticPhase) * radius,
                sin(automaticPhase) * radius,
                0
            )
            input = MotionInput(
                anchorAcceleration: .zero,
                gravityDirection: SIMD3<Float>(0, -1, 0),
                rotationRate: .zero,
                anchorTarget: target
            )
            latestRotationRate = input.rotationRate
            latestShakeDrive = .inactive
        } else {
            let sample = motionController.latestSample()
            if sample.isAvailable, awaitingCalibratedGravity {
                resetSimulation(gravityDirection: sample.gravityDirection)
                awaitingCalibratedGravity = false
            }
            input = MotionInput(
                anchorAcceleration: sample.isAvailable ? sample.userAcceleration : .zero,
                gravityDirection: sample.isAvailable
                    ? sample.gravityDirection
                    : SIMD3<Float>(0, -1, 0),
                rotationRate: sample.isAvailable ? sample.rotationRate : .zero,
                anchorTarget: .zero,
                shakeDrive: sample.isAvailable ? sample.shakeDrive : .inactive
            )
            latestRotationRate = input.rotationRate
            latestShakeDrive = input.shakeDrive
        }

        let frame = simulation.advance(input: input, deltaTime: clampedDeltaTime)
        latestSimulationFrame = frame
        elapsedTime += Float(clampedDeltaTime)
        pendingRenderedWahs += frame.completedWahs
        if earthIsPresented, !isRunningUnitTests {
            audioEngine.update(
                revolutionsPerSecond: frame.revolutionsPerSecond,
                activity: frame.state.activity,
                phase: frame.phase
            )
        }

        if !automaticMode {
            hapticFeedback.update(with: frame)
            if frame.completedWahs > 0 {
                counterService.record(wahs: frame.completedWahs)
                personalWahs = counterService.personalWahs
                lastLocalWahAt = Date()
            }
        }
    }

    private func resolvedInteractionState(for frame: SimulationFrame) -> ToyInteractionState {
        if pointerIsActive {
            return .touching
        }
        if automaticMode {
            return .automatic
        }
        if !motionIsAvailable {
            return .unavailable
        }
        if frame.state.activity > 0.08,
           frame.state.orbitCoherence >= 0.60 {
            return .spinning
        }
        if latestShakeDrive.isActive {
            return .shaking
        }
        return .idle
    }

    private func resetSimulation(gravityDirection: SIMD3<Float>) {
        simulation.reset(gravityDirection: gravityDirection)
        latestSimulationFrame = SimulationFrame(
            state: simulation.state,
            revolutionsPerSecond: 0,
            phase: 0,
            completedWahs: 0
        )
        latestRotationRate = .zero
        pendingRenderedWahs = 0
        automaticRPS = 0
        hapticFeedback.reset()
    }
}

@MainActor
private final class ToyHapticFeedback {
    private let startGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let revolutionGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private var isSpinning = false

    func prepare() {
        startGenerator.prepare()
        revolutionGenerator.prepare()
    }

    func update(with frame: SimulationFrame) {
        let shouldBeSpinning = frame.state.activity > 0.1
            && frame.state.orbitCoherence >= 0.60

        if shouldBeSpinning, !isSpinning {
            startGenerator.impactOccurred(intensity: 0.62)
            startGenerator.prepare()
            isSpinning = true
        } else if frame.state.activity < 0.035,
                  frame.revolutionsPerSecond < 0.42 {
            isSpinning = false
        }

        guard frame.completedWahs > 0 else { return }
        let intensity = min(max(CGFloat(frame.revolutionsPerSecond / 3.2), 0.58), 1)
        revolutionGenerator.impactOccurred(intensity: intensity)
        revolutionGenerator.prepare()
    }

    func reset() {
        isSpinning = false
        prepare()
    }
}
