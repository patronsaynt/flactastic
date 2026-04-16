import Foundation
import MediaPlayer
import AppKit

/// Bridges `PlayerEngine` ↔ macOS `MediaPlayer` framework so that hardware media
/// keys, Control Center's Now Playing widget, AirPods/Bluetooth headset buttons,
/// and Siri can control playback and display the current track's metadata.
///
/// Wiring:
/// - OS → App: remote command handlers on `MPRemoteCommandCenter` route into
///   `PlayerState` / `PlayerEngine`.
/// - App → OS: `updateNowPlaying(...)` pushes title / artist / album / artwork /
///   elapsed time / play state into `MPNowPlayingInfoCenter`.
///
/// Instances are owned by `PlayerState`. The controller holds a *weak* reference
/// back to `PlayerState`, so remote command closures do not form a retain cycle.
@MainActor
final class NowPlayingController {
    private weak var player: PlayerState?

    /// `MPMediaItemArtwork` is expensive to construct (keeps a closure that
    /// decodes image data on demand). Cache by track id so we only rebuild when
    /// the current track actually changes — `syncFromEngine` fires ~10 times a
    /// second during playback.
    private var cachedArtworkTrackID: UUID?
    private var cachedArtwork: MPMediaItemArtwork?

    init() {
        setupRemoteCommands()
    }

    /// Two-step init: `PlayerState` must construct the controller before it can
    /// pass `self` in. Called immediately after `init`.
    func attach(player: PlayerState) {
        self.player = player
    }

    // MARK: - App → OS

    func updateNowPlaying(track: Track?,
                         isPlaying: Bool,
                         currentTime: TimeInterval,
                         duration: TimeInterval?) {
        guard let track else {
            clear()
            return
        }

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = track.title
        if let artist = track.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = track.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let artwork = artwork(for: track) {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        // macOS requires explicit playbackState — unlike iOS, `nowPlayingInfo`
        // alone does not drive the Control Center widget.
        center.playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        cachedArtworkTrackID = nil
        cachedArtwork = nil
    }

    // MARK: - OS → App (remote commands)

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()

        c.playCommand.isEnabled = true
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player?.engine.play() }
            return .success
        }

        c.pauseCommand.isEnabled = true
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player?.engine.pause() }
            return .success
        }

        c.togglePlayPauseCommand.isEnabled = true
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player?.engine.togglePlayPause() }
            return .success
        }

        // Route "next" through PlayerState so repeat-all (and future queue
        // logic) is respected — `PlayerEngine.next()` alone just stops at the
        // end of the queue.
        c.nextTrackCommand.isEnabled = true
        c.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player?.next() }
            return .success
        }

        c.previousTrackCommand.isEnabled = true
        c.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player?.engine.previous() }
            return .success
        }

        c.changePlaybackPositionCommand.isEnabled = true
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let seekEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let target = seekEvent.positionTime
            MainActor.assumeIsolated { self?.player?.engine.seek(to: target) }
            return .success
        }

        // Explicitly disable the commands we don't support so they don't show
        // as ghost controls in Control Center or on hardware remotes.
        c.bookmarkCommand.isEnabled = false
        c.ratingCommand.isEnabled = false
        c.likeCommand.isEnabled = false
        c.dislikeCommand.isEnabled = false
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
        c.changePlaybackRateCommand.isEnabled = false
        c.seekForwardCommand.isEnabled = false
        c.seekBackwardCommand.isEnabled = false
    }

    // MARK: - Artwork cache

    private func artwork(for track: Track) -> MPMediaItemArtwork? {
        if cachedArtworkTrackID == track.id, let cached = cachedArtwork {
            return cached
        }
        cachedArtworkTrackID = track.id
        guard let data = track.artwork, let image = NSImage(data: data) else {
            cachedArtwork = nil
            return nil
        }
        // The handler MUST be `@Sendable` — MediaPlayer stores the artwork in
        // the `nowPlayingInfo` dictionary and bridges it to NSDictionary, which
        // the system then enumerates on its own background queue. Without this
        // annotation, the closure inherits MainActor isolation from the
        // enclosing @MainActor class and crashes the Swift runtime's
        // `_swift_task_checkIsolatedSwift` assertion during that enumeration.
        // Capturing `Data` + `CGSize` (both Sendable) keeps the closure valid.
        let size = image.size
        let artwork = MPMediaItemArtwork(boundsSize: size) { @Sendable _ in
            NSImage(data: data) ?? NSImage(size: size)
        }
        cachedArtwork = artwork
        return artwork
    }
}
