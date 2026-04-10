@preconcurrency import AVFoundation

/// The gapless audio engine. Lives on `@MainActor` so transport methods can be called
/// synchronously from SwiftUI. Heavy decode work is dispatched off the main actor.
@MainActor
final class PlayerEngine {

    // MARK: - Public state (read from PlayerState)

    private(set) var currentTrack: Track?
    private(set) var isPlaying: Bool = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval?
    private(set) var volume: Float = 0.75

    var queue: [Track] { _queue }
    var currentIndex: Int { _currentIndex }

    // MARK: - State update callback

    /// Called on every tick / state change so `PlayerState` can mirror values.
    var onStateUpdate: (@MainActor () -> Void)?

    // MARK: - Private

    private let graph: any AudioGraphProtocol
    private var _queue: [Track] = []
    private var _currentIndex: Int = 0
    private var scheduledEntries: [ScheduledEntry] = []
    private var nextScheduleFrame: AVAudioFramePosition = 0
    private var decodeTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var isPrepared = false
    /// True while the decode task is still scheduling buffers.
    private var isDecoding = false

    /// Chunk size for the output buffer fed to the player node (in canonical frames).
    /// ~0.34 seconds at 192 kHz.
    private let outputChunkFrames: AVAudioFrameCount = 65_536

    /// Chunk size for reading source files in the converter input block (in source frames).
    private let readChunkFrames: AVAudioFrameCount = 32_768

    private struct ScheduledEntry {
        let track: Track
        let startFrame: AVAudioFramePosition
        var endFrame: AVAudioFramePosition
    }

    // MARK: - Init

    init(graph: (any AudioGraphProtocol)? = nil) {
        self.graph = graph ?? AppleAudioGraph()
    }

    private func ensurePrepared() {
        guard !isPrepared else { return }
        do {
            try graph.prepare()
            graph.onConfigurationChange { [weak self] in
                Task { @MainActor in
                    self?.handleConfigurationChange()
                }
            }
            isPrepared = true
        } catch {
            print("[PlayerEngine] Failed to prepare audio graph: \(error)")
        }
    }

    // MARK: - Transport API

    func setQueue(_ tracks: [Track], startAt index: Int) {
        ensurePrepared()
        cancelDecode()
        graph.flush()
        scheduledEntries.removeAll()
        nextScheduleFrame = 0

        _queue = tracks
        _currentIndex = min(index, max(tracks.count - 1, 0))
        if _queue.isEmpty {
            currentTrack = nil
            duration = nil
            currentTime = 0
            isPlaying = false
            notifyStateUpdate()
            return
        }

        currentTrack = _queue[_currentIndex]
        duration = currentTrack?.duration
        currentTime = 0
        notifyStateUpdate()

        startDecoding(from: _currentIndex)
    }

    func play() {
        ensurePrepared()
        graph.play()
        isPlaying = true
        startTick()
        notifyStateUpdate()
    }

    func pause() {
        graph.pause()
        isPlaying = false
        stopTick()
        notifyStateUpdate()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func next() {
        guard !_queue.isEmpty else { return }
        let nextIndex = _currentIndex + 1
        if nextIndex < _queue.count {
            setQueue(_queue, startAt: nextIndex)
            play()
        }
    }

    func previous() {
        guard !_queue.isEmpty else { return }
        if currentTime > 3 {
            setQueue(_queue, startAt: _currentIndex)
            play()
        } else {
            let prevIndex = max(_currentIndex - 1, 0)
            setQueue(_queue, startAt: prevIndex)
            play()
        }
    }

    func seek(to seconds: TimeInterval) {
        guard !_queue.isEmpty else { return }
        let wasPlaying = isPlaying
        cancelDecode()
        graph.flush()
        scheduledEntries.removeAll()
        nextScheduleFrame = 0

        let clamped = max(0, seconds)
        currentTime = clamped
        notifyStateUpdate()

        startDecoding(from: _currentIndex, seekOffset: clamped)
        if wasPlaying { play() }
    }

    func setVolume(_ v: Float) {
        volume = max(0, min(1, v))
        graph.setOutputVolume(volume)
        notifyStateUpdate()
    }

    func volumeUp() {
        setVolume(volume + 0.05)
    }

    func volumeDown() {
        setVolume(volume - 0.05)
    }

    // MARK: - Decode pipeline

    private func cancelDecode() {
        decodeTask?.cancel()
        decodeTask = nil
        isDecoding = false
    }

    private func startDecoding(from index: Int, seekOffset: TimeInterval = 0) {
        let queue = _queue
        let canonical = graph.canonicalFormat
        let readChunk = readChunkFrames
        let outputChunk = outputChunkFrames
        let graphRef = graph

        isDecoding = true

        decodeTask = Task.detached(priority: .userInitiated) { [weak self] in
            var trackIndex = index
            var isFirstTrack = true

            while trackIndex < queue.count, !Task.isCancelled {
                let track = queue[trackIndex]

                do {
                    let file = try AVAudioFile(
                        forReading: track.url,
                        commonFormat: .pcmFormatFloat32,
                        interleaved: false
                    )
                    let sourceFormat = file.processingFormat

                    // Handle seek offset for the first track.
                    if isFirstTrack && seekOffset > 0 {
                        let seekFrame = AVAudioFramePosition(seekOffset * sourceFormat.sampleRate)
                        let clampedFrame = min(seekFrame, file.length - 1)
                        file.framePosition = max(0, clampedFrame)
                    }

                    // Update duration on main actor for the current track.
                    let fileDuration = Double(file.length) / sourceFormat.sampleRate
                    if isFirstTrack {
                        await MainActor.run { [weak self] in
                            self?.duration = fileDuration
                        }
                    }

                    // Create a fresh converter per track to avoid stale internal state.
                    guard let converter = AVAudioConverter(from: sourceFormat, to: canonical) else {
                        print("[PlayerEngine] Cannot create converter for \(track.title)")
                        trackIndex += 1
                        isFirstTrack = false
                        continue
                    }
                    converter.sampleRateConverterQuality = .max

                    // Record start frame.
                    let startFrame = await MainActor.run { [weak self] () -> AVAudioFramePosition in
                        return self?.nextScheduleFrame ?? 0
                    }

                    var totalScheduledFrames: AVAudioFramePosition = 0

                    // Use a pull-based converter: call convert() in a loop, each call fills
                    // one output chunk. The input block reads from the file on demand.
                    // This keeps the converter's SRC state continuous (no clicks between chunks).
                    let fileBox = UncheckedSendableBox(file)
                    var fileExhausted = false

                    while !fileExhausted, !Task.isCancelled {
                        guard let destBuffer = AVAudioPCMBuffer(
                            pcmFormat: canonical,
                            frameCapacity: outputChunk
                        ) else { break }

                        var convError: NSError?
                        let readSize = readChunk
                        let srcFmt = sourceFormat

                        let status = converter.convert(to: destBuffer, error: &convError) { _, outStatus in
                            let f = fileBox.value
                            let remaining = AVAudioFrameCount(f.length - f.framePosition)
                            if remaining == 0 {
                                outStatus.pointee = .endOfStream
                                return nil
                            }
                            let toRead = min(readSize, remaining)
                            guard let srcBuf = AVAudioPCMBuffer(
                                pcmFormat: srcFmt,
                                frameCapacity: toRead
                            ) else {
                                outStatus.pointee = .endOfStream
                                return nil
                            }
                            do {
                                try f.read(into: srcBuf, frameCount: toRead)
                            } catch {
                                outStatus.pointee = .endOfStream
                                return nil
                            }
                            if srcBuf.frameLength == 0 {
                                outStatus.pointee = .endOfStream
                                return nil
                            }
                            outStatus.pointee = .haveData
                            return srcBuf
                        }

                        if destBuffer.frameLength > 0 {
                            totalScheduledFrames += AVAudioFramePosition(destBuffer.frameLength)
                            graphRef.schedule(destBuffer, completionCallbackType: .dataConsumed) { _ in }
                        }

                        if status == .endOfStream || status == .error {
                            if status == .error, let convError {
                                print("[PlayerEngine] Converter error for \(track.title): \(convError)")
                            }
                            fileExhausted = true
                        }
                    }

                    // Record entry for track-boundary tracking.
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        let entry = ScheduledEntry(
                            track: track,
                            startFrame: startFrame,
                            endFrame: startFrame + totalScheduledFrames
                        )
                        self.scheduledEntries.append(entry)
                        self.nextScheduleFrame = entry.endFrame
                    }

                } catch {
                    if Task.isCancelled { return }
                    print("[PlayerEngine] Error opening \(track.title): \(error)")
                }

                isFirstTrack = false
                trackIndex += 1
            }

            // Mark decode complete on main actor.
            await MainActor.run { [weak self] in
                self?.isDecoding = false
            }
        }
    }

    // MARK: - Time tracking tick

    private func startTick() {
        guard tickTask == nil else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updateTime()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopTick() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func updateTime() {
        guard let sampleTime = graph.currentPlayerSampleTime() else { return }
        let canonicalRate = graph.canonicalFormat.sampleRate

        // Find which track the current playback position falls in.
        for entry in scheduledEntries {
            if sampleTime >= entry.startFrame && sampleTime < entry.endFrame {
                let framesIntoTrack = sampleTime - entry.startFrame
                currentTime = Double(framesIntoTrack) / canonicalRate

                if currentTrack?.id != entry.track.id {
                    currentTrack = entry.track
                    duration = entry.track.duration ?? Double(entry.endFrame - entry.startFrame) / canonicalRate
                    if let idx = _queue.firstIndex(where: { $0.id == entry.track.id }) {
                        _currentIndex = idx
                    }
                }
                notifyStateUpdate()

                // Clean up entries that are fully in the past.
                while let first = scheduledEntries.first, first.endFrame <= sampleTime {
                    scheduledEntries.removeFirst()
                }
                return
            }
        }

        // If sampleTime is past all entries AND decoding is done, playback finished.
        if !isDecoding, !scheduledEntries.isEmpty, sampleTime >= scheduledEntries.last!.endFrame {
            isPlaying = false
            stopTick()
            notifyStateUpdate()
        }
    }

    // MARK: - Configuration change

    private func handleConfigurationChange() {
        guard isPrepared else { return }
        let wasPlaying = isPlaying
        let savedTime = currentTime
        let savedIndex = _currentIndex

        cancelDecode()
        graph.flush()
        scheduledEntries.removeAll()
        nextScheduleFrame = 0

        // The engine was stopped by the system; re-prepare it.
        graph.reprepare()

        if !_queue.isEmpty {
            startDecoding(from: savedIndex, seekOffset: savedTime)
            if wasPlaying { play() }
        }
    }

    // MARK: - Helpers

    private func notifyStateUpdate() {
        onStateUpdate?()
    }
}

// MARK: - Concurrency helpers

/// Wraps a non-Sendable value for use in contexts where we know the access pattern is safe.
struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
