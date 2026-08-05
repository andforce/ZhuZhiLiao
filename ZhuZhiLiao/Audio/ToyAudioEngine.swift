@preconcurrency import AVFAudio
import Foundation

struct EarthAudioVoiceDescriptor: Equatable, Identifiable, Sendable {
    let id: String
    let activeUntil: Int64
    let normalizedStartPhase: Double
}

enum EarthAudioVoicePlanner {
    static func voices(
        nodes: [EarthNode],
        serverNow: Int64,
        serverClockOffsetMilliseconds: Int64,
        localWahAt: Date?
    ) -> [EarthAudioVoiceDescriptor] {
        let localActiveUntil = localWahAt.map {
            Int64($0.timeIntervalSince1970 * 1_000)
                + EarthActivity.durationMilliseconds
                + serverClockOffsetMilliseconds
        }
        var result: [EarthAudioVoiceDescriptor] = []

        for node in nodes {
            let localDeadline = node.highlightsMe ? localActiveUntil : nil
            let activeUntil = max(node.activeUntil ?? 0, localDeadline ?? 0)
            guard activeUntil > serverNow else { continue }

            let voiceCount: Int
            switch node.kind {
            case .player:
                voiceCount = 1
            case .cluster:
                voiceCount = max(node.activeCount ?? 0, localDeadline == nil ? 0 : 1)
            }

            for index in 0..<voiceCount {
                let id = "\(node.kind.rawValue):\(node.id):\(index)"
                result.append(EarthAudioVoiceDescriptor(
                    id: id,
                    activeUntil: activeUntil,
                    normalizedStartPhase: normalizedPhase(for: id)
                ))
            }
        }

        return result.sorted { $0.id < $1.id }
    }

    static func normalizedGain(voiceCount: Int, isMuted: Bool = false) -> Float {
        guard voiceCount > 0, !isMuted else { return 0 }
        return 0.8 / sqrt(Float(voiceCount))
    }

    private static func normalizedPhase(for value: String) -> Double {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Double(hash % 10_000) / 10_000
    }
}

@MainActor
final class ToyAudioEngine: NSObject {
    private struct EarthVoice {
        let descriptor: EarthAudioVoiceDescriptor
        let player: AVAudioPlayer
    }

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var varispeed = AVAudioUnitVarispeed()
    private var loopBuffer: AVAudioPCMBuffer?
    private var earthVoices: [String: EarthVoice] = [:]
    private var desiredEarthVoices: [EarthAudioVoiceDescriptor] = []
    private var isConfigured = false
    private var wantsPlayback = false
    private var isEarthPresented = false
    private var isEarthMuted = false

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
            for voice in earthVoices.values where !voice.player.isPlaying {
                voice.player.play()
            }
        } catch {
            // 声音不可用时玩法仍继续；下次生命周期恢复会再次尝试。
        }
    }

    func pause() {
        wantsPlayback = false
        player.pause()
        earthVoices.values.forEach { $0.player.pause() }
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
        engine.mainMixerNode.outputVolume = isEarthPresented
            ? 0
            : 0.85 * pow(min(max(activity, 0), 1), 1.3)
    }

    func setEarthPresented(_ isPresented: Bool) {
        guard isEarthPresented != isPresented else { return }
        isEarthPresented = isPresented
        if isPresented {
            engine.mainMixerNode.outputVolume = 0
        } else {
            desiredEarthVoices = []
            reconcileEarthVoices(with: [])
        }
    }

    func updateEarthVoices(_ descriptors: [EarthAudioVoiceDescriptor]) {
        guard isEarthPresented else { return }
        desiredEarthVoices = descriptors
        reconcileEarthVoices(with: descriptors)
    }

    func setEarthMuted(_ isMuted: Bool) {
        guard isEarthMuted != isMuted else { return }
        isEarthMuted = isMuted
        updateEarthVoiceVolumes()
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

    private func reconcileEarthVoices(with descriptors: [EarthAudioVoiceDescriptor]) {
        let requested = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })

        for id in Array(earthVoices.keys) where requested[id] == nil {
            guard let removed = earthVoices.removeValue(forKey: id) else { continue }
            removed.player.setVolume(0, fadeDuration: 0.08)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(90))
                removed.player.stop()
            }
        }

        guard let url = Bundle.main.url(
            forResource: "zhuzhiliao-loop",
            withExtension: "m4a"
        ) else { return }

        for descriptor in descriptors where earthVoices[descriptor.id] == nil {
            do {
                let earthPlayer = try AVAudioPlayer(contentsOf: url)
                earthPlayer.numberOfLoops = -1
                earthPlayer.volume = 0
                earthPlayer.prepareToPlay()
                earthPlayer.currentTime = earthPlayer.duration * descriptor.normalizedStartPhase
                earthVoices[descriptor.id] = EarthVoice(
                    descriptor: descriptor,
                    player: earthPlayer
                )
                if wantsPlayback {
                    earthPlayer.play()
                }
            } catch {
                // 单个地球声部失败时保留其余声部和地球画面。
            }
        }

        updateEarthVoiceVolumes()
    }

    private func updateEarthVoiceVolumes() {
        let gain = EarthAudioVoicePlanner.normalizedGain(
            voiceCount: earthVoices.count,
            isMuted: isEarthMuted
        )
        earthVoices.values.forEach { voice in
            voice.player.setVolume(gain, fadeDuration: 0.12)
        }
    }

    private func rebuildAndResumeIfNeeded() {
        let earthDescriptors = desiredEarthVoices
        earthVoices.values.forEach { $0.player.stop() }
        earthVoices.removeAll()
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
        if isEarthPresented {
            reconcileEarthVoices(with: earthDescriptors)
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
            earthVoices.values.forEach { $0.player.pause() }
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
            guard let self, self.wantsPlayback else { return }
            self.start()
        }
    }
}
