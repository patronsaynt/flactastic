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

    /// Install a tap on the main mixer for analysis (FFT / visualization).
    /// The block is called on a background audio thread; consumers must hop
    /// to the main actor before publishing observed state.
    func installAnalysisTap(bufferSize: AVAudioFrameCount,
                            _ block: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)
    func removeAnalysisTap()
}

// MARK: - Apple AVAudioEngine implementation

final class AppleAudioGraph: AudioGraphProtocol, @unchecked Sendable {
    /// The canonical processing format, derived from the output device's sample rate.
    /// Set during `prepare()` / `reprepare()`. Always stereo Float32 non-interleaved.
    private(set) var canonicalFormat: AVAudioFormat

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var configChangeObserver: Any?
    private var isAttached = false
    private var hasAnalysisTap = false

    init() {
        // Placeholder; real format is set in prepare() from the device rate.
        canonicalFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    }

    deinit {
        if let obs = configChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        engine.stop()
    }

    func prepare() throws {
        canonicalFormat = makeCanonicalFormat()

        if !isAttached {
            engine.attach(playerNode)
            isAttached = true
        }
        engine.connect(playerNode, to: engine.mainMixerNode, format: canonicalFormat)
        try engine.start()
    }

    func reprepare() {
        canonicalFormat = makeCanonicalFormat()
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

    // MARK: - Private

    func installAnalysisTap(bufferSize: AVAudioFrameCount,
                            _ block: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) {
        if hasAnalysisTap {
            engine.mainMixerNode.removeTap(onBus: 0)
            hasAnalysisTap = false
        }
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, when in
            block(buffer, when)
        }
        hasAnalysisTap = true
    }

    func removeAnalysisTap() {
        guard hasAnalysisTap else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        hasAnalysisTap = false
    }

    private func makeCanonicalFormat() -> AVAudioFormat {
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let deviceRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44_100
        return AVAudioFormat(standardFormatWithSampleRate: deviceRate, channels: 2)!
    }
}
