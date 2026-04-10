import AVFoundation

// MARK: - Protocol for portability

protocol AudioGraphProtocol: AnyObject, Sendable {
    /// The canonical processing format that all buffers must be in before scheduling.
    var canonicalFormat: AVAudioFormat { get }

    /// Prepare the audio graph for playback. Call once at initialization.
    func prepare() throws

    /// Schedule a PCM buffer for playback (must be in canonicalFormat).
    func schedule(_ buffer: AVAudioPCMBuffer, completionCallbackType: AVAudioPlayerNodeCompletionCallbackType,
                  completionHandler: @escaping @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void)

    /// Start or resume playback.
    func play()

    /// Pause (keeps scheduled buffers).
    func pause()

    /// Stop and flush all scheduled buffers.
    func flush()

    /// Whether the player node is currently playing.
    var isNodePlaying: Bool { get }

    /// The current render-time sample position on the player node's timeline, or nil if not yet rendering.
    func currentPlayerSampleTime() -> AVAudioFramePosition?

    /// Set the output volume (0.0 ... 1.0).
    func setOutputVolume(_ volume: Float)

    /// Register a callback for engine configuration changes (e.g. headphones plugged in).
    func onConfigurationChange(_ handler: @escaping @Sendable () -> Void)
}

// MARK: - Apple AVAudioEngine implementation

final class AppleAudioGraph: AudioGraphProtocol, @unchecked Sendable {
    let canonicalFormat: AVAudioFormat

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var configChangeObserver: Any?

    init() {
        // Canonical: 192 kHz, Float32, deinterleaved, stereo
        canonicalFormat = AVAudioFormat(standardFormatWithSampleRate: 192_000, channels: 2)!
    }

    deinit {
        if let obs = configChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        engine.stop()
    }

    func prepare() throws {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: canonicalFormat)
        try engine.start()
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
