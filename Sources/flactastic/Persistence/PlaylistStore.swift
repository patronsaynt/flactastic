import Foundation
import Observation

@Observable
@MainActor
final class PlaylistStore {
    var playlists: [Playlist] = []

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("flactastic", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("playlists.json")
    }()

    // MARK: - Persistence

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            playlists = try JSONDecoder().decode([Playlist].self, from: data)
        } catch {
            print("[PlaylistStore] Failed to load playlists: \(error)")
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(playlists)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[PlaylistStore] Failed to save playlists: \(error)")
        }
    }

    // MARK: - CRUD

    @discardableResult
    func createPlaylist(name: String) -> Playlist {
        let playlist = Playlist(name: name)
        playlists.append(playlist)
        save()
        return playlist
    }

    func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        save()
    }

    func renamePlaylist(id: UUID, name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = name
        save()
    }

    /// Updates editable playlist metadata (name, description, custom cover image).
    /// Pass `nil` for `customArtwork` to clear the cover.
    func updatePlaylistMetadata(
        id: UUID,
        name: String,
        description: String?,
        customArtwork: Data?
    ) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = name
        playlists[index].description = description
        playlists[index].customArtwork = customArtwork
        save()
    }

    // MARK: - Track operations

    func addTracks(_ tracks: [Track], to playlistID: UUID, relativeTo rootURL: URL?) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              let rootURL else { return }

        let rootPath = rootURL.path
        for track in tracks {
            let trackPath = track.url.path
            if trackPath.hasPrefix(rootPath) {
                let relative = String(trackPath.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
                playlists[index].entries.append(PlaylistEntry(relativePath: relative))
            }
        }
        save()
    }

    func removeEntries(at offsets: IndexSet, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].entries.remove(atOffsets: offsets)
        save()
    }

    func removeEntries(ids: Set<UUID>, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].entries.removeAll { ids.contains($0.id) }
        save()
    }

    func moveEntries(from source: IndexSet, to destination: Int, in playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].entries.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Resolution

    /// Resolves playlist entries to live Track objects from the library.
    func resolvedTracks(for playlist: Playlist, in library: LibraryStore) -> [Track] {
        guard let rootURL = library.rootURL else { return [] }

        let tracksByPath = Dictionary(library.tracks.map { ($0.url.path, $0) },
                                      uniquingKeysWith: { first, _ in first })

        return playlist.entries.compactMap { entry in
            let absolutePath = rootURL.appendingPathComponent(entry.relativePath).path
            return tracksByPath[absolutePath]
        }
    }

    // MARK: - Reconciliation

    /// Remove entries from all playlists whose source files no longer exist in the library.
    func reconcile(with library: LibraryStore) {
        guard let rootURL = library.rootURL else { return }

        let libraryPaths = Set(library.tracks.map { $0.url.path })
        var changed = false

        for i in playlists.indices {
            let before = playlists[i].entries.count
            playlists[i].entries.removeAll { entry in
                let absolutePath = rootURL.appendingPathComponent(entry.relativePath).path
                return !libraryPaths.contains(absolutePath)
            }
            if playlists[i].entries.count != before {
                changed = true
            }
        }

        if changed { save() }
    }
}
