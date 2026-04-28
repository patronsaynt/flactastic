import Foundation
import Observation

/// Centralises "add tracks to playlist" so duplicate handling lives in one
/// place. Call sites invoke `request(...)`; if the target playlist already
/// contains any of the tracks, `pending` is populated and `ContentView`'s
/// confirmation dialog asks the user how to proceed. Otherwise the tracks
/// are added immediately.
@Observable
@MainActor
final class PlaylistAddCoordinator {
    struct PendingAdd: Identifiable {
        let id = UUID()
        let playlistID: UUID
        let playlistName: String
        let tracks: [Track]
        let rootURL: URL?
        let duplicateCount: Int
        var totalCount: Int { tracks.count }
        var newCount: Int { totalCount - duplicateCount }
    }

    var pending: PendingAdd?

    func request(
        tracks: [Track],
        playlistID: UUID,
        playlistName: String,
        rootURL: URL?,
        store: PlaylistStore
    ) {
        guard !tracks.isEmpty else { return }
        let dupes = store.duplicateCount(of: tracks, in: playlistID, relativeTo: rootURL)
        if dupes == 0 {
            store.addTracks(tracks, to: playlistID, relativeTo: rootURL)
            return
        }
        pending = PendingAdd(
            playlistID: playlistID,
            playlistName: playlistName,
            tracks: tracks,
            rootURL: rootURL,
            duplicateCount: dupes
        )
    }

    func resolveAddAll(store: PlaylistStore) {
        guard let p = pending else { return }
        store.addTracks(p.tracks, to: p.playlistID, relativeTo: p.rootURL)
        pending = nil
    }

    func resolveSkipDuplicates(store: PlaylistStore) {
        guard let p = pending else { return }
        store.addTracks(p.tracks, to: p.playlistID, relativeTo: p.rootURL, skipDuplicates: true)
        pending = nil
    }

    func cancel() {
        pending = nil
    }

    /// Creates a new playlist with `name` and adds `tracks` to it. Used by the
    /// inline "New Playlist…" text field in the Add-to-Playlist menus.
    func createPlaylistAndAdd(name: String, tracks: [Track], rootURL: URL?, store: PlaylistStore) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tracks.isEmpty else { return }
        let playlist = store.createPlaylist(name: trimmed)
        store.addTracks(tracks, to: playlist.id, relativeTo: rootURL)
    }
}
