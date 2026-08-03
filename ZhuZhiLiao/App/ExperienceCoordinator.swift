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
    private var simulation: ToySimulation
    private var lastFrameTime: CFTimeInterval?
    private var elapsedTime: Float = 0
    private var automaticPhase: Float = 0
    private var hudElapsed: Float = 0
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
        isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastFrameTime = nil
        motionController.start()
        motionIsAvailable = motionController.isAvailable

        if !motionIsAvailable {
            automaticMode = true
        }

        guard !isRunningUnitTests else { return }
        audioEngine.start()
        counterService.start()
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        lastFrameTime = nil
        motionController.stop()

        guard !isRunningUnitTests else { return }
        audioEngine.pause()
        counterService.stop()
    }

    func recalibrate() {
        motionController.resetCalibration()
        simulation.reset()
        lastFrameTime = nil
    }

    func toggleAutomaticMode() {
        automaticMode.toggle()
        automaticPhase = 0
        simulation.reset()
        if !automaticMode {
            motionController.resetCalibration()
        }
    }

    func frame(at timestamp: CFTimeInterval) -> RenderSnapshot {
        let deltaTime: TimeInterval
        if let lastFrameTime {
            deltaTime = min(max(timestamp - lastFrameTime, 0), 0.05)
        } else {
            deltaTime = 1.0 / 60.0
        }
        self.lastFrameTime = timestamp

        let input: MotionInput
        let rotationRate: SIMD3<Float>
        if automaticMode {
            automaticPhase += Float(deltaTime) * 3.15 * 2 * .pi
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
            rotationRate = input.rotationRate
        } else {
            let sample = motionController.latestSample()
            input = MotionInput(
                anchorAcceleration: sample.userAcceleration,
                gravityDirection: sample.gravityDirection,
                rotationRate: sample.rotationRate
            )
            rotationRate = sample.rotationRate
        }

        let frame = simulation.advance(input: input, deltaTime: deltaTime)
        elapsedTime += Float(deltaTime)
        hudElapsed += Float(deltaTime)

        if frame.completedWahs > 0, !automaticMode {
            counterService.record(wahs: frame.completedWahs)
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
        }

        if !isRunningUnitTests {
            audioEngine.update(
                revolutionsPerSecond: frame.revolutionsPerSecond,
                activity: frame.state.activity,
                phase: frame.phase
            )
        }

        if hudElapsed >= 0.12 {
            hudElapsed = 0
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
            rotationRate: rotationRate,
            emittedWahs: frame.completedWahs
        )
    }
}

