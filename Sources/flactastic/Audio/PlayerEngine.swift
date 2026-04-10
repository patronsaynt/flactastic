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
    private var converterCache: [ConverterKey: AVAudioConverter] = [:]
    private var isPrepared = false

    /// Cap how far ahead we schedule (in canonical frames). ~10 seconds at 192 kHz.
    private let lookAheadFrames: AVAudioFrameCount = 192_000 * 10

    /// Chunk size for reading source files (in source frames).
    private let readChunkFrames: AVAudioFrameCount = 65_536

    private struct ScheduledEntry {
        let track: Track
        let startFrame: AVAudioFramePosition
        var endFrame: AVAudioFramePosition
    }

    private struct ConverterKey: Hashable {
        let sampleRate: Double
        let channelCount: UInt32
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
        converterCache.removeAll()
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
        // If we're past 3 seconds, restart; otherwise go to previous track.
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

        // Clamp to valid range
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
    }

    private func startDecoding(from index: Int, seekOffset: TimeInterval = 0) {
        let queue = _queue
        let canonical = graph.canonicalFormat
        let chunkFrames = readChunkFrames
        let graphRef = graph

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

                    // Get or create converter.
                    let converter = try await self?.getOrCreateConverter(
                        sourceFormat: sourceFormat, destFormat: canonical
                    )

                    guard let converter else { break }

                    // Record start frame.
                    let startFrame = await MainActor.run { [weak self] () -> AVAudioFramePosition in
                        return self?.nextScheduleFrame ?? 0
                    }

                    var totalScheduledFrames: AVAudioFramePosition = 0

                    // Read and schedule in chunks.
                    while file.framePosition < file.length, !Task.isCancelled {
                        let remainingSourceFrames = AVAudioFrameCount(file.length - file.framePosition)
                        let framesToRead = min(chunkFrames, remainingSourceFrames)

                        guard let sourceBuffer = AVAudioPCMBuffer(
                            pcmFormat: sourceFormat,
                            frameCapacity: framesToRead
                        ) else { break }
                        try file.read(into: sourceBuffer, frameCount: framesToRead)

                        if sourceBuffer.frameLength == 0 { break }

                        // Convert to canonical format.
                        let outputFrameCapacity = AVAudioFrameCount(
                            Double(sourceBuffer.frameLength) * canonical.sampleRate / sourceFormat.sampleRate
                        ) + 1024
                        guard let destBuffer = AVAudioPCMBuffer(
                            pcmFormat: canonical,
                            frameCapacity: outputFrameCapacity
                        ) else { break }

                        var error: NSError?
                        // The converter input block is called synchronously during convert(),
                        // so the mutable capture is safe. Use a Sendable wrapper to satisfy Swift 6.
                        let inputBuffer = UncheckedSendableBox(sourceBuffer)
                        let consumed = UncheckedSendableBox(MutableFlag(false))
                        let status = converter.convert(to: destBuffer, error: &error) { _, outStatus in
                            if consumed.value.value {
                                outStatus.pointee = .endOfStream
                                return nil
                            }
                            consumed.value.value = true
                            outStatus.pointee = .haveData
                            return inputBuffer.value
                        }

                        if status == .error { break }
                        if destBuffer.frameLength == 0 { continue }

                        totalScheduledFrames += AVAudioFramePosition(destBuffer.frameLength)

                        graphRef.schedule(destBuffer, completionCallbackType: .dataConsumed) { _ in }
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
                    print("[PlayerEngine] Error decoding \(track.title): \(error)")
                }

                isFirstTrack = false
                trackIndex += 1
            }
        }
    }

    @MainActor
    private func getOrCreateConverter(
        sourceFormat: AVAudioFormat,
        destFormat: AVAudioFormat
    ) throws -> AVAudioConverter {
        let key = ConverterKey(
            sampleRate: sourceFormat.sampleRate,
            channelCount: sourceFormat.channelCount
        )
        if let cached = converterCache[key] {
            return cached
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: destFormat) else {
            throw NSError(domain: "PlayerEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create converter from \(sourceFormat) to \(destFormat)"])
        }
        converter.sampleRateConverterQuality = .max
        converterCache[key] = converter
        return converter
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
        for (_, entry) in scheduledEntries.enumerated() {
            if sampleTime >= entry.startFrame && sampleTime < entry.endFrame {
                let framesIntoTrack = sampleTime - entry.startFrame
                currentTime = Double(framesIntoTrack) / canonicalRate

                if currentTrack?.id != entry.track.id {
                    currentTrack = entry.track
                    duration = entry.track.duration ?? Double(entry.endFrame - entry.startFrame) / canonicalRate
                    // Update the queue index.
                    if let idx = _queue.firstIndex(where: { $0.id == entry.track.id }) {
                        _currentIndex = idx
                    }
                }
                notifyStateUpdate()

                // Clean up entries that are fully in the past.
                let pastEntries = scheduledEntries.prefix(while: { $0.endFrame <= sampleTime })
                if !pastEntries.isEmpty {
                    scheduledEntries.removeFirst(pastEntries.count)
                }
                return
            }
        }

        // If sampleTime is past all entries, playback finished.
        if !scheduledEntries.isEmpty && sampleTime >= scheduledEntries.last!.endFrame {
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
        scheduledEntries.removeAll()
        nextScheduleFrame = 0
        converterCache.removeAll()

        do {
            try graph.prepare()
        } catch {
            print("[PlayerEngine] Failed to restart after config change: \(error)")
            return
        }

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

/// A simple mutable boolean wrapped in a reference type.
final class MutableFlag: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}
