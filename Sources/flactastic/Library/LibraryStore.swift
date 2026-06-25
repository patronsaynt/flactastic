import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class LibraryStore {
    enum ScanState: Equatable {
        case idle
        case scanning
        case refreshing
        case done(count: Int)
        case failed(String)
    }

    var rootURL: URL?
    var tracks: [Track] = []
    var scanState: ScanState = .idle
    /// Flips to `true` once the app's initial library load resolves (either a
    /// successful scan, a failure, or a confirmed no-op when there's nothing
    /// to scan). The UI gates its first paint on this so albums/tracks don't
    /// visibly populate during startup. Only the *first* resolution sets it;
    /// later manual refreshes do not reset it.
    var hasCompletedInitialLoad: Bool = false

    /// Per-album artwork cache. Keyed by album ID (artist|name). A key's
    /// *presence* means the album has been seeded; the value may be nil when
    /// the album genuinely has no artwork. Only written by:
    ///   • `seedAlbumArtworkCache()` — after scans and imports
    ///   • `invalidateAlbumArtwork(albumID:)` — called by the album editor
    /// Track-level edits (`updateTrack`) deliberately never touch this, so
    /// setting per-track artwork does not bleed into the album cover display.
    private var albumArtworkCache: [String: Data?] = [:]

    var albums: [Album] {
        // Pass 1: group by normalized album name.
        let byName = Dictionary(grouping: tracks) {
            ($0.album ?? "Unknown Album").lowercased()
        }

        var result: [Album] = []

        for (_, nameGroup) in byName {
            // Pass 2: subdivide by albumArtist only when at least one track has it set.
            // This lets tracks with the same album name but different `artist` tags (and
            // no albumArtist) merge into one compilation instead of splitting.
            let hasAlbumArtist = nameGroup.contains(where: { $0.albumArtist != nil })

            let subgroups: [[Track]]
            if hasAlbumArtist {
                let sub = Dictionary(grouping: nameGroup) { $0.albumArtist ?? "Unknown Artist" }
                subgroups = Array(sub.values)
            } else {
                subgroups = [nameGroup]
            }

            for group in subgroups {
                let sorted = group.sorted { ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
                let aa = sorted.first(where: { $0.albumArtist != nil })?.albumArtist
                let distinct = Set(sorted.compactMap(\.artist))
                let displayArtist: String?
                if let aa { displayArtist = aa }
                else if distinct.count > 1 { displayArtist = "Various Artists" }
                else { displayArtist = distinct.first }

                let key = "\(aa ?? displayArtist ?? "Unknown Artist")|\(sorted.first?.album ?? "Unknown Album")"
                result.append(Album(
                    id: key,
                    name: sorted.first?.album ?? "Unknown Album",
                    artist: displayArtist,
                    albumArtist: aa,
                    year: sorted.first?.year,
                    genre: sorted.first?.genre,
                    artwork: albumArtworkCache[key] ?? Self.dominantArtwork(in: sorted),
                    tracks: sorted
                ))
            }
        }

        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Returns the artwork shared by the most tracks in a group.
    /// Ties are broken by first appearance, so a single outlier track with a
    /// unique cover (e.g. a single artwork set on one track) does not replace
    /// the artwork that represents the album as a whole.
    private static func dominantArtwork(in tracks: [Track]) -> Data? {
        let artworks = tracks.compactMap(\.artwork)
        guard !artworks.isEmpty else { return nil }
        // Count occurrences of each distinct artwork. Data hashing is cheap
        // (Swift samples bytes rather than hashing the full payload) and
        // equality short-circuits on length, so this is safe for typical
        // album sizes.
        var counts: [Data: Int] = [:]
        var firstSeen: [Data: Int] = [:] // track insertion order for tie-breaking
        for (i, art) in artworks.enumerated() {
            if counts[art] == nil { firstSeen[art] = i }
            counts[art, default: 0] += 1
        }
        return counts.max {
            let (a, ca) = $0; let (b, cb) = $1
            if ca != cb { return ca < cb }           // prefer higher count
            return (firstSeen[a] ?? 0) > (firstSeen[b] ?? 0) // earlier = wins tie
        }?.key
    }

    private let scanner = LibraryScanner()
    private var scanTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?

    /// Persists relativePath → UUID so Track identities survive restarts.
    /// Loaded in `openFolder` and consulted during every scan.
    private(set) var trackIDStore = TrackIDStore()

    func album(for track: Track) -> Album? {
        albums.first { $0.tracks.contains { $0.id == track.id } }
    }

    /// Seeds `albumArtworkCache` for any album not yet present. Safe to call
    /// repeatedly — existing entries are never overwritten, so artwork locked in
    /// by a prior seed or by the album editor is preserved through rescans.
    func seedAlbumArtworkCache() {
        for album in albums {
            guard albumArtworkCache[album.id] == nil else { continue }
            albumArtworkCache[album.id] = album.artwork
        }
    }

    /// Called by the album editor after saving. Clears the cached artwork for
    /// `albumID` so the next `albums` access recomputes it from the freshly-
    /// written track files (dominant artwork = the one just saved to all tracks).
    func invalidateAlbumArtwork(albumID: String) {
        albumArtworkCache.removeValue(forKey: albumID)
        seedAlbumArtworkCache()
    }

    /// Replaces the stored `Track` matching `id` with `updated`.
    /// Because `albums` is a computed property, callers in album-detail views
    /// and the collection grid will automatically see the new metadata.
    func updateTrack(id: UUID, with updated: Track) {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[i] = updated
    }

    /// Applies many track updates atomically in a single `tracks` assignment.
    /// Prefer this over per-track `updateTrack` when renaming fields that affect
    /// album grouping (artist/album name): a piecemeal update would briefly
    /// split the album across two grouping keys and cause detail views to
    /// render "Album not found" mid-operation.
    func replaceTracks(_ updated: [Track]) {
        guard !updated.isEmpty else { return }
        let byID = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
        tracks = tracks.map { byID[$0.id] ?? $0 }
    }

    /// Appends tracks that entered the library via the Import menu (rather
    /// than a folder scan). Deduplicates by URL — if the same file path is
    /// already known, the existing entry wins so its UUID (and any queue/
    /// playlist membership) stays stable.
    func addImportedTracks(_ imported: [Track]) {
        guard !imported.isEmpty else { return }
        let existing = Set(tracks.map { $0.url })
        var fresh = imported.filter { !existing.contains($0.url) }
        guard !fresh.isEmpty else { return }
        // Assign stable IDs to newly-imported tracks so playlist membership
        // survives the next app restart.
        if let url = rootURL {
            fresh = applyStableIDs(to: fresh, rootURL: url)
            trackIDStore.save()
        }
        tracks = (tracks + fresh).sortedForLibrary()
        normaliseArtistTags()
        seedAlbumArtworkCache()
    }

    func openFolder(_ url: URL) {
        scanTask?.cancel()
        metadataTask?.cancel()
        rootURL = url
        scanState = .scanning
        tracks = []

        // Load the sidecar before scanning so assign() returns persisted UUIDs.
        trackIDStore.load(from: url)

        scanTask = Task { [scanner] in
            do {
                let cheap = try await scanner.scan(root: url)
                if Task.isCancelled { return }
                // Rewrite ephemeral UUIDs → stable IDs from the sidecar.
                let stable = self.applyStableIDs(to: cheap, rootURL: url)
                self.trackIDStore.save()
                self.tracks = stable
                self.scanState = .done(count: stable.count)
                // Note: we deliberately do NOT flip `hasCompletedInitialLoad`
                // here. The cheap scan gives us URLs but no metadata, so
                // album grouping would churn as artist/album tags stream in.
                // The flag flips once `startMetadataLoad` finishes.
                self.startMetadataLoad()
            } catch {
                if Task.isCancelled { return }
                self.scanState = .failed(String(describing: error))
                withAnimation(.easeOut(duration: 0.35)) {
                    self.hasCompletedInitialLoad = true
                }
            }
        }
    }

    func refreshLibrary() {
        guard let url = rootURL else { return }
        guard scanState != .scanning else { return }

        scanTask?.cancel()
        metadataTask?.cancel()
        scanState = .refreshing

        scanTask = Task { [scanner] in
            do {
                let scanned = try await scanner.scan(root: url)
                if Task.isCancelled { return }

                let existingByURL = Dictionary(
                    self.tracks.map { ($0.url, $0) },
                    uniquingKeysWith: { _, last in last }
                )

                // Assign stable IDs only to genuinely new files — existing
                // in-memory tracks already carry their stable UUID from the
                // last openFolder/refresh call.
                let rawNewStubs = scanned.filter { existingByURL[$0.url] == nil }
                let stableNewStubs = self.applyStableIDs(to: rawNewStubs, rootURL: url)
                if !stableNewStubs.isEmpty { self.trackIDStore.save() }

                let stableByURL = Dictionary(
                    stableNewStubs.map { ($0.url, $0) },
                    uniquingKeysWith: { _, last in last }
                )
                let merged: [Track] = scanned.map { stub in
                    existingByURL[stub.url] ?? stableByURL[stub.url] ?? stub
                }

                self.tracks = merged
                self.scanState = .done(count: merged.count)

                if !stableNewStubs.isEmpty {
                    self.startMetadataLoadForTracks(stableNewStubs)
                }
            } catch {
                if Task.isCancelled { return }
                self.scanState = .failed(String(describing: error))
            }
        }
    }

    private func startMetadataLoadForTracks(_ newTracks: [Track]) {
        let snapshot = newTracks
        metadataTask = Task { [scanner] in
            await withTaskGroup(of: Track.self) { group in
                let maxConcurrent = 8
                var index = 0
                var inFlight = 0

                func submit(_ t: Track) {
                    group.addTask { [scanner] in await scanner.loadMetadata(for: t) }
                }

                while index < snapshot.count && inFlight < maxConcurrent {
                    submit(snapshot[index]); index += 1; inFlight += 1
                }
                while let updated = await group.next() {
                    if Task.isCancelled { group.cancelAll(); return }
                    self.updateTrack(id: updated.id, with: updated)
                    if index < snapshot.count { submit(snapshot[index]); index += 1 }
                }
                if !Task.isCancelled {
                    self.tracks = self.tracks.sortedForLibrary()
                    self.normaliseArtistTags()
                    self.seedAlbumArtworkCache()
                }
            }
        }
    }

    /// Rewrites each track's `id` to the stable UUID from `trackIDStore`,
    /// using the track's relative path as the lookup key.  New paths are
    /// assigned a fresh UUID and recorded.
    ///
    /// **Does not save** — callers must call `trackIDStore.save()` once after
    /// the full batch to avoid per-track disk writes.
    @discardableResult
    private func applyStableIDs(to tracks: [Track], rootURL: URL) -> [Track] {
        let rootPath = rootURL.path
        return tracks.map { track in
            guard track.url.path.hasPrefix(rootPath) else { return track }
            let rel = String(track.url.path.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
            let stableID = trackIDStore.assign(fileURL: track.url, relativePath: rel)
            guard stableID != track.id else { return track }
            return Track(
                id: stableID,
                url: track.url,
                title: track.title,
                artist: track.artist,
                albumArtist: track.albumArtist,
                album: track.album,
                trackNumber: track.trackNumber,
                duration: track.duration,
                artwork: track.artwork,
                fileFormat: track.fileFormat,
                sampleRate: track.sampleRate,
                bitDepth: track.bitDepth,
                genre: track.genre,
                year: track.year,
                isCompilation: track.isCompilation,
                dateAdded: track.dateAdded
            )
        }
    }

    private func startMetadataLoad() {
        let snapshot = tracks
        metadataTask = Task { [scanner] in
            // Cap concurrency at 8 so we don't thrash the disk.
            await withTaskGroup(of: (Int, Track).self) { group in
                let maxConcurrent = 8
                var index = 0
                var inFlight = 0

                func submit(_ i: Int, _ t: Track) {
                    group.addTask { [scanner] in
                        let updated = await scanner.loadMetadata(for: t)
                        return (i, updated)
                    }
                }

                while index < snapshot.count && inFlight < maxConcurrent {
                    submit(index, snapshot[index])
                    index += 1
                    inFlight += 1
                }

                while let (i, updated) = await group.next() {
                    if Task.isCancelled { group.cancelAll(); return }
                    if i < self.tracks.count, self.tracks[i].id == updated.id {
                        self.tracks[i] = updated
                    }
                    if index < snapshot.count {
                        submit(index, snapshot[index])
                        index += 1
                    }
                }

                // Re-sort after metadata is loaded so albums group properly.
                if !Task.isCancelled {
                    self.tracks = self.tracks.sortedForLibrary()

                    // Reveal the UI as soon as the grid is stable-sorted —
                    // i.e. the moment the Collection is genuinely populated.
                    // The two refinements below (tag normalisation + artwork
                    // cache seeding) are non-essential to first paint and each
                    // walks the whole library, so they used to add a visible
                    // tail to the loading cover even though the data was ready.
                    // We now run them *after* the flip so the home page appears
                    // in lockstep with the Collection being done. The
                    // withAnimation drives LoadingCoverView's .transition.
                    if !self.hasCompletedInitialLoad {
                        withAnimation(.easeOut(duration: 0.35)) {
                            self.hasCompletedInitialLoad = true
                        }
                    }

                    self.normaliseArtistTags()
                    self.seedAlbumArtworkCache()
                }
            }
        }
    }
}
