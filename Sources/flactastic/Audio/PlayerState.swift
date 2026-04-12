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
    var repeatMode: RepeatMode = .off

    /// The original (unshuffled) queue, stored so we can restore order when shuffle is turned off.
    private var originalQueue: [Track] = []

    var queue: [Track] { engine.queue }
    var currentIndex: Int { engine.currentIndex }

    init(graph: (any AudioGraphProtocol)? = nil) {
        engine = PlayerEngine(graph: graph)
        engine.onStateUpdate = { [weak self] in
            self?.syncFromEngine()
        }
    }

    /// Toggle shuffle on/off, reshuffling or restoring the current queue.
    func toggleShuffle() {
        let wasShuffled = isShuffleEnabled
        isShuffleEnabled.toggle()

        let currentQueue = engine.queue
        guard !currentQueue.isEmpty else { return }
        let playing = currentTrack

        if !wasShuffled {
            // Turning shuffle ON: save original order, shuffle queue
            originalQueue = currentQueue
            var shuffled = currentQueue
            // Remove the currently playing track, shuffle the rest, put it first
            if let playing, let idx = shuffled.firstIndex(where: { $0.id == playing.id }) {
                shuffled.remove(at: idx)
                shuffled.shuffle()
                shuffled.insert(playing, at: 0)
            } else {
                shuffled.shuffle()
            }
            let wasPlaying = engine.isPlaying
            engine.setQueue(shuffled, startAt: 0)
            if wasPlaying { engine.play() }
        } else {
            // Turning shuffle OFF: restore original order
            guard !originalQueue.isEmpty else { return }
            let restoreIndex: Int
            if let playing {
                restoreIndex = originalQueue.firstIndex(where: { $0.id == playing.id }) ?? 0
            } else {
                restoreIndex = 0
            }
            let wasPlaying = engine.isPlaying
            engine.setQueue(originalQueue, startAt: restoreIndex)
            if wasPlaying { engine.play() }
            originalQueue = []
        }
    }

    /// Store the original queue when an external caller sets up a shuffled queue
    /// (e.g. "Shuffle" button on album/playlist detail views).
    func setOriginalQueue(_ tracks: [Track]) {
        originalQueue = tracks
    }

    private func syncFromEngine() {
        currentTrack = engine.currentTrack
        isPlaying = engine.isPlaying
        currentTime = engine.currentTime
        duration = engine.duration
        volume = engine.volume
    }
}
