import Combine
import Foundation
import UIKit

@MainActor
final class ExperienceCoordinator: ObservableObject {
    @Published private(set) var revolutionsPerSecond: Float = 0
    @Published private(set) var activity: Float = 0
    @Published private(set) var stats = CounterStats(online: 0, visitors: 0, visits: 0, wahs: 0)
    @Published private(set) var personalWahs = 0
    @Published private(set) var motionIsAvailable = false
    @Published private(set) var isRunning = false
    @Published var automaticMode = false

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
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        motionController.start()
        motionIsAvailable = motionController.isAvailable

        if !motionIsAvailable {
            automaticMode = true
        }

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
        motionController.resetCalibration()
        if automaticMode {
            resetSimulation(gravityDirection: SIMD3<Float>(0, -1, 0))
            awaitingCalibratedGravity = false
        } else {
            awaitingCalibratedGravity = true
        }
    }

    func toggleAutomaticMode() {
        automaticMode.toggle()
        automaticPhase = 0
        if automaticMode {
            resetSimulation(gravityDirection: SIMD3<Float>(0, -1, 0))
            awaitingCalibratedGravity = false
        } else {
            motionController.resetCalibration()
            awaitingCalibratedGravity = true
        }
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
        if automaticMode {
            automaticPhase += Float(clampedDeltaTime) * 3.15 * 2 * .pi
            let force = SIMD3<Float>(
                cos(automaticPhase) * 0.82,
                sin(automaticPhase) * 0.82,
                sin(automaticPhase * 0.63) * 0.28
            )
            input = MotionInput(
                anchorAcceleration: force,
                gravityDirection: SIMD3<Float>(0, -1, 0),
                rotationRate: SIMD3<Float>(0, 0, 0.08)
            )
            latestRotationRate = input.rotationRate
        } else {
            let sample = motionController.latestSample()
            guard sample.isAvailable else { return }
            if awaitingCalibratedGravity {
                resetSimulation(gravityDirection: sample.gravityDirection)
                awaitingCalibratedGravity = false
            }
            input = MotionInput(
                anchorAcceleration: sample.userAcceleration,
                gravityDirection: sample.gravityDirection,
                rotationRate: sample.rotationRate
            )
            latestRotationRate = sample.rotationRate
        }

        let frame = simulation.advance(input: input, deltaTime: clampedDeltaTime)
        latestSimulationFrame = frame
        elapsedTime += Float(clampedDeltaTime)
        pendingRenderedWahs += frame.completedWahs

        if !automaticMode {
            hapticFeedback.update(with: frame)
            if frame.completedWahs > 0 {
                counterService.record(wahs: frame.completedWahs)
            }
        }
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
            || frame.revolutionsPerSecond > 0.72

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
