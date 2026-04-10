@preconcurrency import AVFoundation
import os

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
    private var isDecoding = false
    private var seekTimeOffset: TimeInterval = 0

    /// Generation counter — incremented on every cancel to invalidate stale decode tasks.
    private let generation = OSAllocatedUnfairLock(initialState: UInt64(0))

    /// Backpressure: caps how many canonical frames are scheduled but not yet consumed.
    private let throttle = BufferThrottle()

    /// Output chunk: ~0.37s at 44.1 kHz. Small enough for responsive seek, large enough to avoid overhead.
    private let outputChunkFrames: AVAudioFrameCount = 16_384

    /// Read chunk for converter input block (source frames).
    private let readChunkFrames: AVAudioFrameCount = 8_192

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
            // Set throttle limit based on actual device sample rate (~10 seconds of audio).
            let rate = graph.canonicalFormat.sampleRate
            throttle.setLimit(Int64(rate * 10))

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
        seekTimeOffset = 0

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
        if isPlaying { pause() } else { play() }
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
        seekTimeOffset = clamped
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

    func volumeUp() { setVolume(volume + 0.05) }
    func volumeDown() { setVolume(volume - 0.05) }

    // MARK: - Decode pipeline

    private func cancelDecode() {
        decodeTask?.cancel()
        decodeTask = nil
        generation.withLock { $0 &+= 1 }
        throttle.reset()
        isDecoding = false
    }

    private func startDecoding(from index: Int, seekOffset: TimeInterval = 0) {
        let queue = _queue
        let canonical = graph.canonicalFormat
        let readChunk = readChunkFrames
        let outputChunk = outputChunkFrames
        let graphRef = graph
        let throttle = self.throttle
        let myGeneration = generation.withLock { $0 }
        let generation = self.generation

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

                    // Seek within the first track.
                    if isFirstTrack && seekOffset > 0 {
                        let seekFrame = AVAudioFramePosition(seekOffset * sourceFormat.sampleRate)
                        file.framePosition = max(0, min(seekFrame, file.length - 1))
                    }

                    // Update duration for the current track.
                    let fileDuration = Double(file.length) / sourceFormat.sampleRate
                    if isFirstTrack {
                        await MainActor.run { [weak self] in
                            self?.duration = fileDuration
                        }
                    }

                    // Check if we can do a zero-conversion passthrough.
                    let needsConverter = sourceFormat.sampleRate != canonical.sampleRate
                        || sourceFormat.channelCount != canonical.channelCount

                    // Create converter only if needed.
                    var converter: AVAudioConverter?
                    if needsConverter {
                        guard let conv = AVAudioConverter(from: sourceFormat, to: canonical) else {
                            print("[PlayerEngine] Cannot create converter for \(track.title)")
                            trackIndex += 1
                            isFirstTrack = false
                            continue
                        }
                        conv.sampleRateConverterQuality = .max
                        converter = conv
                    }

                    // Create entry eagerly so updateTime() can track this track immediately.
                    // endFrame = .max is a sentinel meaning "still decoding".
                    let (startFrame, entryIndex) = await MainActor.run { [weak self] () -> (AVAudioFramePosition, Int) in
                        guard let self else { return (0, 0) }
                        let sf = self.nextScheduleFrame
                        let entry = ScheduledEntry(track: track, startFrame: sf, endFrame: .max)
                        self.scheduledEntries.append(entry)
                        return (sf, self.scheduledEntries.count - 1)
                    }

                    var totalScheduledFrames: AVAudioFramePosition = 0

                    if needsConverter, let converter {
                        // --- Converter path: pull-based conversion ---
                        let fileBox = UncheckedSendableBox(file)
                        var fileExhausted = false

                        while !fileExhausted, !Task.isCancelled {
                            if generation.withLock({ $0 }) != myGeneration { return }

                            guard let destBuffer = AVAudioPCMBuffer(
                                pcmFormat: canonical, frameCapacity: outputChunk
                            ) else { break }

                            var convError: NSError?
                            let srcFmt = sourceFormat
                            let chunkSize = readChunk

                            let status = converter.convert(to: destBuffer, error: &convError) { _, outStatus in
                                let f = fileBox.value
                                let remaining = AVAudioFrameCount(f.length - f.framePosition)
                                if remaining == 0 {
                                    outStatus.pointee = .endOfStream
                                    return nil
                                }
                                let toRead = min(chunkSize, remaining)
                                guard let srcBuf = AVAudioPCMBuffer(
                                    pcmFormat: srcFmt, frameCapacity: toRead
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
                                let frameCount = Int64(destBuffer.frameLength)

                                await throttle.acquire(frames: frameCount)
                                if generation.withLock({ $0 }) != myGeneration { return }

                                totalScheduledFrames += AVAudioFramePosition(frameCount)
                                graphRef.schedule(destBuffer, completionCallbackType: .dataConsumed) { _ in
                                    if generation.withLock({ $0 }) == myGeneration {
                                        throttle.release(frames: frameCount)
                                    }
                                }
                            }

                            if status == .endOfStream || status == .error {
                                if status == .error, let convError {
                                    print("[PlayerEngine] Converter error for \(track.title): \(convError)")
                                }
                                fileExhausted = true
                            }
                        }
                    } else {
                        // --- Passthrough path: read directly into schedule buffers ---
                        while file.framePosition < file.length, !Task.isCancelled {
                            if generation.withLock({ $0 }) != myGeneration { return }

                            let remaining = AVAudioFrameCount(file.length - file.framePosition)
                            let toRead = min(outputChunk, remaining)

                            guard let destBuffer = AVAudioPCMBuffer(
                                pcmFormat: canonical, frameCapacity: toRead
                            ) else { break }

                            try file.read(into: destBuffer, frameCount: toRead)
                            if destBuffer.frameLength == 0 { break }

                            let frameCount = Int64(destBuffer.frameLength)

                            await throttle.acquire(frames: frameCount)
                            if generation.withLock({ $0 }) != myGeneration { return }

                            totalScheduledFrames += AVAudioFramePosition(frameCount)
                            graphRef.schedule(destBuffer, completionCallbackType: .dataConsumed) { _ in
                                if generation.withLock({ $0 }) == myGeneration {
                                    throttle.release(frames: frameCount)
                                }
                            }
                        }
                    }

                    // Finalize entry: replace .max sentinel with actual endFrame.
                    if generation.withLock({ $0 }) != myGeneration { return }
                    let actualEnd = startFrame + totalScheduledFrames
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if entryIndex < self.scheduledEntries.count,
                           self.scheduledEntries[entryIndex].track.id == track.id {
                            self.scheduledEntries[entryIndex].endFrame = actualEnd
                        }
                        self.nextScheduleFrame = actualEnd
                    }

                } catch {
                    if Task.isCancelled { return }
                    print("[PlayerEngine] Error opening \(track.title): \(error)")
                }

                isFirstTrack = false
                trackIndex += 1
            }

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
        guard let sampleTime = graph.currentPlayerSampleTime(), sampleTime >= 0 else { return }
        let canonicalRate = graph.canonicalFormat.sampleRate

        for entry in scheduledEntries {
            // endFrame == .max means "still decoding" — treat as if it extends to infinity.
            if sampleTime >= entry.startFrame && (entry.endFrame == .max || sampleTime < entry.endFrame) {
                let framesIntoTrack = sampleTime - entry.startFrame
                currentTime = seekTimeOffset + Double(framesIntoTrack) / canonicalRate

                if currentTrack?.id != entry.track.id {
                    currentTrack = entry.track
                    if entry.endFrame != .max {
                        duration = entry.track.duration ?? Double(entry.endFrame - entry.startFrame) / canonicalRate
                    } else {
                        duration = entry.track.duration
                    }
                    if let idx = _queue.firstIndex(where: { $0.id == entry.track.id }) {
                        _currentIndex = idx
                    }
                    // Reset seek offset for subsequent tracks (they start at 0).
                    seekTimeOffset = 0
                }
                notifyStateUpdate()

                // Clean up fully-consumed, finalized entries.
                while let first = scheduledEntries.first,
                      first.endFrame != .max,
                      first.endFrame <= sampleTime {
                    scheduledEntries.removeFirst()
                }
                return
            }
        }

        // Past all entries and decoding done → playback finished.
        // Only trigger if the last entry is finalized (endFrame != .max).
        if !isDecoding,
           let lastEntry = scheduledEntries.last,
           lastEntry.endFrame != .max,
           sampleTime >= lastEntry.endFrame {
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

        graph.reprepare()
        // Update throttle limit for new device rate.
        let rate = graph.canonicalFormat.sampleRate
        throttle.setLimit(Int64(rate * 10))

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

// MARK: - Buffer throttle (backpressure)

/// Caps in-flight scheduled frames so we never flood the player node's buffer queue.
/// Thread-safe; used from the decode task and completion callbacks concurrently.
final class BufferThrottle: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: ThrottleState())

    private struct ThrottleState {
        var inFlight: Int64 = 0
        var limit: Int64 = 441_000 // default ~10s at 44.1 kHz, updated at prepare
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    func setLimit(_ limit: Int64) {
        state.withLock { $0.limit = limit }
    }

    func acquire(frames: Int64) async {
        let shouldWait: Bool = state.withLock { s in
            s.inFlight += frames
            return s.inFlight > s.limit
        }
        if !shouldWait { return }

        await withCheckedContinuation { cont in
            state.withLock { $0.waiters.append(cont) }
        }
    }

    func release(frames: Int64) {
        let waiter: CheckedContinuation<Void, Never>? = state.withLock { s in
            s.inFlight -= frames
            if s.inFlight <= s.limit, !s.waiters.isEmpty {
                return s.waiters.removeFirst()
            }
            return nil
        }
        waiter?.resume()
    }

    /// Cancel all backpressure — unblock any waiting decode task so it can check cancellation.
    func reset() {
        let waiters: [CheckedContinuation<Void, Never>] = state.withLock { s in
            s.inFlight = 0
            let w = s.waiters
            s.waiters.removeAll()
            return w
        }
        for w in waiters { w.resume() }
    }
}

// MARK: - Concurrency helpers

struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
