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

    var queue: [Track] { engine.queue }
    var currentIndex: Int { engine.currentIndex }

    init(graph: (any AudioGraphProtocol)? = nil) {
        engine = PlayerEngine(graph: graph)
        engine.onStateUpdate = { [weak self] in
            self?.syncFromEngine()
        }
    }

    private func syncFromEngine() {
        currentTrack = engine.currentTrack
        isPlaying = engine.isPlaying
        currentTime = engine.currentTime
        duration = engine.duration
        volume = engine.volume
    }
}
