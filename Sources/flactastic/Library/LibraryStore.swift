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

    private let scanner = LibraryScanner()
    private var scanTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?

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
