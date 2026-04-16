import Foundation
import Observation

enum RepeatMode: Sendable {
    case off, all, one
}

@Observable
@MainActor
final class PlayerState {
    let engine: PlayerEngine

    var currentTrack: Track?
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval?
    var volume: Float = 0.75
    var isShuffleEnabled: Bool = false
    var repeatMode: RepeatMode = .off {
        didSet {
            guard oldValue != repeatMode else { return }
            engine.isRepeatOne = (repeatMode == .one)
        }
    }

    /// The original (unshuffled) queue, stored so we can restore order when shuffle is turned off.
    private var originalQueue: [Track] = []

    /// Track IDs that were added via Play Next / Add to Queue — used to render the
    /// yellow indicator in the queue panel. Cleared whenever a fresh queue is started
    /// (e.g. via Play All, a double-click, or track-list playback).
    var userQueuedTrackIDs: Set<UUID> = []

    /// Display name of the source the current queue was started from — e.g. the
    /// album name or playlist name. Used for the "Next from: <source>" section in
    /// the queue panel.
    var playbackSource: String? = nil

    /// Whether the queue panel is currently visible.
    var isQueueVisible: Bool = false

    /// Mirror of `engine.queue`. Stored (not computed) so SwiftUI observes changes
    /// even when `currentTrack`/`duration` don't change — e.g. appending to a
    /// single-track queue, where the current track stays the same but the queue grows.
    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int = 0

    func isUserQueued(_ track: Track) -> Bool {
        userQueuedTrackIDs.contains(track.id)
    }

    init(graph: (any AudioGraphProtocol)? = nil) {
        engine = PlayerEngine(graph: graph)
        engine.onStateUpdate = { [weak self] in
            self?.syncFromEngine()
        }
    }

    /// Toggle shuffle on/off. Shuffling applies ONLY to source (album/playlist)
    /// tracks — user-queued tracks always retain their "next up" position
    /// immediately after the currently-playing track, in their original order.
    func toggleShuffle() {
        let wasShuffled = isShuffleEnabled
        isShuffleEnabled.toggle()

        let currentQueue = engine.queue
        guard !currentQueue.isEmpty, let playing = currentTrack else { return }
        let curIdx = engine.currentIndex

        // Partition the upcoming portion into user-queued (preserve order) vs source.
        let upcoming: [Track] = (curIdx + 1) < currentQueue.count
            ? Array(currentQueue[(curIdx + 1)...])
            : []
        let userUpcoming = upcoming.filter { userQueuedTrackIDs.contains($0.id) }
        let sourceUpcoming = upcoming.filter { !userQueuedTrackIDs.contains($0.id) }

        if !wasShuffled {
            // Turning ON: snapshot the full queue for later restoration, then
            // rebuild as [current] + [user-queued preserved] + [shuffled source].
            originalQueue = currentQueue
            var shuffledSource = sourceUpcoming
            shuffledSource.shuffle()
            let newQueue = [playing] + userUpcoming + shuffledSource
            // reorderQueue rearranges without flushing — playback continues uninterrupted.
            engine.reorderQueue(newQueue, currentIndex: 0)
        } else {
            // Turning OFF: restore source order from originalQueue, keeping
            // any user-queued tracks at "next up" (they're immune to shuffle).
            guard !originalQueue.isEmpty,
                  let origIdx = originalQueue.firstIndex(where: { $0.id == playing.id }) else {
                originalQueue = []
                return
            }
            // Strip any user-queued tracks from the restored source order so
            // they don't appear twice (we re-inject userUpcoming below).
            let before = Array(originalQueue[0..<origIdx])
                .filter { !userQueuedTrackIDs.contains($0.id) }
            let after = Array(originalQueue[(origIdx + 1)...])
                .filter { !userQueuedTrackIDs.contains($0.id) }
            let newQueue = before + [playing] + userUpcoming + after
            engine.reorderQueue(newQueue, currentIndex: before.count)
            originalQueue = []
        }
    }

    /// Advance to the next track, respecting repeat mode.
    func next() {
        let q = engine.queue
        guard !q.isEmpty else { return }
        let nextIndex = engine.currentIndex + 1
        if nextIndex < q.count {
            engine.setQueue(q, startAt: nextIndex)
            engine.play()
        } else if repeatMode == .all {
            engine.setQueue(q, startAt: 0)
            engine.play()
        } else {
            // End of queue, no repeat — stop playback
            engine.pause()
        }
    }

    /// Store the original queue when an external caller sets up a shuffled queue
    /// (e.g. "Shuffle" button on album/playlist detail views).
    func setOriginalQueue(_ tracks: [Track]) {
        originalQueue = tracks
    }

    // MARK: - Queue API

    /// Start a fresh playback queue. Clears any user-queued markers — this is what
    /// Play All, double-click, and similar "start playing X" actions should call
    /// instead of talking to the engine directly.
    func startFreshQueue(_ tracks: [Track], startAt index: Int = 0, source: String? = nil) {
        userQueuedTrackIDs.removeAll()
        playbackSource = source
        engine.setQueue(tracks, startAt: index)
    }

    /// Insert tracks immediately after the current track. If nothing is playing yet,
    /// this starts a fresh queue from the given tracks.
    func playNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        let fresh = tracks.map { $0.withNewID() }
        let ids = fresh.map { $0.id }

        if engine.queue.isEmpty {
            userQueuedTrackIDs = Set(ids)
            playbackSource = nil
            engine.setQueue(fresh, startAt: 0)
            engine.play()
        } else {
            userQueuedTrackIDs.formUnion(ids)
            engine.insertTracks(fresh, at: engine.currentIndex + 1)
        }
    }

    /// Append tracks to the user-queued section — i.e. after the current track and
    /// any already-user-queued tracks, but *before* the remaining source tracks.
    /// If the queue is empty, this behaves like `playNext` and starts playback.
    func addToQueue(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        let fresh = tracks.map { $0.withNewID() }
        let ids = fresh.map { $0.id }

        if engine.queue.isEmpty {
            userQueuedTrackIDs = Set(ids)
            playbackSource = nil
            engine.setQueue(fresh, startAt: 0)
            engine.play()
            return
        }

        // Skip past any already-user-queued tracks that sit between the current
        // track and the source section so new additions append to the user-queue
        // section, matching Spotify-style behavior.
        let q = engine.queue
        var insertIdx = engine.currentIndex + 1
        while insertIdx < q.count && userQueuedTrackIDs.contains(q[insertIdx].id) {
            insertIdx += 1
        }

        userQueuedTrackIDs.formUnion(ids)
        if insertIdx >= q.count {
            engine.appendTracks(fresh)
        } else {
            engine.insertTracks(fresh, at: insertIdx)
        }
    }

    /// Reorder upcoming queue items without interrupting playback. `source` and
    /// `destination` are relative to the section that fired `.onMove`;
    /// `baseEngineIndex` maps them to absolute positions in the engine queue.
    /// Delegates to `engine.reorderQueue` which avoids flushing in-flight audio.
    func moveQueueItems(from source: IndexSet, to destination: Int, baseEngineIndex: Int) {
        guard !engine.queue.isEmpty else { return }
        let curIdx = engine.currentIndex
        var q = engine.queue

        // Translate section-relative indices → full engine-queue indices.
        let engineSource = IndexSet(source.map { $0 + baseEngineIndex })
        let engineDest = destination + baseEngineIndex

        q.move(fromOffsets: engineSource, toOffset: engineDest)
        engine.reorderQueue(q, currentIndex: curIdx)
    }

    /// Jump to a specific index within the current queue.
    func jumpTo(index: Int) {
        let q = engine.queue
        guard index >= 0, index < q.count else { return }
        engine.setQueue(q, startAt: index)
        engine.play()
    }

    private func syncFromEngine() {
        currentTrack = engine.currentTrack
        isPlaying = engine.isPlaying
        currentTime = engine.currentTime
        duration = engine.duration
        volume = engine.volume
        queue = engine.queue
        currentIndex = engine.currentIndex
    }
}
