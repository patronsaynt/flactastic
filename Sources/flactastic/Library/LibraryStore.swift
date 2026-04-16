import Foundation
import Observation

@Observable
@MainActor
final class LibraryStore {
    enum ScanState: Equatable {
        case idle
        case scanning
        case done(count: Int)
        case failed(String)
    }

    var rootURL: URL?
    var tracks: [Track] = []
    var scanState: ScanState = .idle

    var albums: [Album] {
        let grouped = Dictionary(grouping: tracks) { track in
            "\(track.artist ?? "Unknown Artist")|\(track.album ?? "Unknown Album")"
        }
        return grouped.map { key, tracks in
            let sorted = tracks.sorted { ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
            return Album(
                id: key,
                name: sorted.first?.album ?? "Unknown Album",
                artist: sorted.first?.artist,
                year: sorted.first?.year,
                genre: sorted.first?.genre,
                artwork: sorted.first(where: { $0.artwork != nil })?.artwork,
                tracks: sorted
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private let scanner = LibraryScanner()
    private var scanTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?

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
