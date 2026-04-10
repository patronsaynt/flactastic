import AVFoundation

// MARK: - Protocol for portability

protocol AudioGraphProtocol: AnyObject, Sendable {
    var canonicalFormat: AVAudioFormat { get }
    func prepare() throws
    func reprepare()
    func schedule(_ buffer: AVAudioPCMBuffer, completionCallbackType: AVAudioPlayerNodeCompletionCallbackType,
                  completionHandler: @escaping @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void)
    func play()
    func pause()
    func flush()
    var isNodePlaying: Bool { get }
    func currentPlayerSampleTime() -> AVAudioFramePosition?
    func setOutputVolume(_ volume: Float)
    func onConfigurationChange(_ handler: @escaping @Sendable () -> Void)
}

// MARK: - Apple AVAudioEngine implementation

final class AppleAudioGraph: AudioGraphProtocol, @unchecked Sendable {
    let canonicalFormat: AVAudioFormat

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var configChangeObserver: Any?
    private var isAttached = false

    init() {
        canonicalFormat = AVAudioFormat(standardFormatWithSampleRate: 192_000, channels: 2)!
    }

    deinit {
        if let obs = configChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        engine.stop()
    }

    func prepare() throws {
        if !isAttached {
            engine.attach(playerNode)
            isAttached = true
        }
        engine.connect(playerNode, to: engine.mainMixerNode, format: canonicalFormat)
        try engine.start()
    }

    func reprepare() {
        // After a config change the engine was stopped by the system.
        // Re-connect and restart without re-attaching.
        engine.connect(playerNode, to: engine.mainMixerNode, format: canonicalFormat)
        try? engine.start()
    }

    func schedule(_ buffer: AVAudioPCMBuffer,
                  completionCallbackType: AVAudioPlayerNodeCompletionCallbackType,
                  completionHandler: @escaping @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void) {
        playerNode.scheduleBuffer(buffer, completionCallbackType: completionCallbackType, completionHandler: completionHandler)
    }

    func play() {
        if !engine.isRunning {
            try? engine.start()
        }
        playerNode.play()
    }

    func pause() {
        playerNode.pause()
    }

    func flush() {
        playerNode.stop()
    }

    var isNodePlaying: Bool {
        playerNode.isPlaying
    }

    func currentPlayerSampleTime() -> AVAudioFramePosition? {
        guard let nodeTime = playerNode.lastRenderTime, nodeTime.isSampleTimeValid else { return nil }
        guard let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return nil }
        return playerTime.sampleTime
    }

    func setOutputVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = max(0, min(1, volume))
    }

    func onConfigurationChange(_ handler: @escaping @Sendable () -> Void) {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { _ in
            handler()
        }
    }
}
