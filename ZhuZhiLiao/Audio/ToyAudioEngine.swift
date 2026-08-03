@preconcurrency import AVFAudio
import Foundation

@MainActor
final class ToyAudioEngine: NSObject {
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var varispeed = AVAudioUnitVarispeed()
    private var loopBuffer: AVAudioPCMBuffer?
    private var isConfigured = false
    private var wantsPlayback = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(receiveInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(receiveMediaServicesReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(receiveRouteChange(_:)),
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
        // 竹知了的声音是核心玩法，因此即使响铃/静音开关处于静音状态也应播放。
        // 保留混音选项，避免启动玩具声音时打断用户正在播放的其他音频。
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    private func rebuildAndResumeIfNeeded() {
        player.stop()
        engine.stop()
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        varispeed = AVAudioUnitVarispeed()
        loopBuffer = nil
        isConfigured = false
        if wantsPlayback {
            start()
        }
    }

    @objc
    nonisolated private func receiveInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else {
            return
        }
        let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        Task { @MainActor [weak self] in
            self?.handleInterruption(rawType: rawType, rawOptions: rawOptions)
        }
    }

    private func handleInterruption(rawType: UInt, rawOptions: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {
        case .began:
            player.pause()
            engine.pause()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if wantsPlayback, options.contains(.shouldResume) {
                start()
            }
        @unknown default:
            break
        }
    }

    @objc
    nonisolated private func receiveMediaServicesReset(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.rebuildAndResumeIfNeeded()
        }
    }

    @objc
    nonisolated private func receiveRouteChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self, self.wantsPlayback, !self.engine.isRunning else { return }
            self.start()
        }
    }
}
