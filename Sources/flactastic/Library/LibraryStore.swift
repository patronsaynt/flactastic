import Foundation
import Observation

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
                    artwork: sorted.first(where: { $0.artwork != nil })?.artwork,
                    tracks: sorted
                ))
            }
        }

        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private let scanner = LibraryScanner()
    private var scanTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?

    func album(for track: Track) -> Album? {
        albums.first { $0.tracks.contains { $0.id == track.id } }
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
        let fresh = imported.filter { !existing.contains($0.url) }
        guard !fresh.isEmpty else { return }
        tracks = (tracks + fresh).sortedForLibrary()
    }

    func openFolder(_ url: URL) {
        scanTask?.cancel()
        metadataTask?.cancel()
        rootURL = url
        scanState = .scanning
        tracks = []

        scanTask = Task { [scanner] in
            do {
                let cheap = try await scanner.scan(root: url)
                if Task.isCancelled { return }
                self.tracks = cheap
                self.scanState = .done(count: cheap.count)
                self.startMetadataLoad()
            } catch {
                if Task.isCancelled { return }
                self.scanState = .failed(String(describing: error))
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
                let merged: [Track] = scanned.map { stub in existingByURL[stub.url] ?? stub }

                self.tracks = merged
                self.scanState = .done(count: merged.count)

                let newStubs = merged.filter { existingByURL[$0.url] == nil }
                if !newStubs.isEmpty {
                    self.startMetadataLoadForTracks(newStubs)
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
                }
            }
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
                }
            }
        }
    }
}
