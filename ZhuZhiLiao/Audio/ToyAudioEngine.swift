@preconcurrency import AVFAudio
import Foundation

@MainActor
final class ToyAudioEngine: NSObject {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()
    private var loopBuffer: AVAudioPCMBuffer?
    private var isConfigured = false
    private var wantsPlayback = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        wantsPlayback = true
        do {
            if !isConfigured {
                try configureGraph()
            }
            try activateAudioSession()
            if !engine.isRunning {
                try engine.start()
            }
            if !player.isPlaying {
                player.play()
            }
        } catch {
            // 声音不可用时玩法仍继续；下次生命周期恢复会再次尝试。
        }
    }

    func pause() {
        wantsPlayback = false
        player.pause()
        engine.pause()
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    func update(revolutionsPerSecond: Float, activity: Float, phase: Float) {
        guard isConfigured else { return }

        let normalizedSpeed = max(revolutionsPerSecond / 2.33, 0.000_1)
        let baseRate = min(max(pow(normalizedSpeed, 0.7), 0.6), 1.5)
        let detuneCents = 50 * sin(phase + 0.9) * min(max(activity * 1.6, 0), 1)
        let phaseRate = pow(2, detuneCents / 1_200)
        varispeed.rate = min(max(baseRate * phaseRate, 0.6), 1.5)
        engine.mainMixerNode.outputVolume = 0.85 * pow(min(max(activity, 0), 1), 1.3)
    }

    private func configureGraph() throws {
        guard let url = Bundle.main.url(
            forResource: "zhuzhiliao-loop",
            withExtension: "m4a"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)

        engine.attach(player)
        engine.attach(varispeed)
        engine.connect(player, to: varispeed, format: buffer.format)
        engine.connect(varispeed, to: engine.mainMixerNode, format: buffer.format)
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        engine.mainMixerNode.outputVolume = 0
        loopBuffer = buffer
        isConfigured = true
    }

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    private func rebuildAndResumeIfNeeded() {
        player.stop()
        engine.stop()
        engine.detach(player)
        engine.detach(varispeed)
        loopBuffer = nil
        isConfigured = false
        if wantsPlayback {
            start()
        }
    }

    @objc
    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {
        case .began:
            player.pause()
            engine.pause()
        case .ended:
            if wantsPlayback {
                start()
            }
        @unknown default:
            break
        }
    }

    @objc
    private func handleMediaServicesReset() {
        rebuildAndResumeIfNeeded()
    }

    @objc
    private func handleRouteChange() {
        if wantsPlayback, !engine.isRunning {
            start()
        }
    }
}

