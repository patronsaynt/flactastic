import Foundation
import Observation
import SwiftUI

/// View-model for the Organizer page. Owns the live preview state and drives
/// the executor. Reads tracks from `LibraryStore`; writes back via
/// `LibraryStore.replaceTracks` after a successful apply so the rest of the app
/// (Collection, queues, playlists) sees the new URLs without a rescan.
@Observable
@MainActor
final class OrganizerModel {
    var operations: [OrganizerOperation] = []
    var isPreviewStale: Bool = true
    var isApplying: Bool = false
    var lastError: String?
    var lastResultMessage: String?
    /// Phase + fractional progress (0...1) of an in-flight apply. nil when
    /// nothing is running. Drives the progress bar in the Organizer view.
    var applyPhaseLabel: String?
    var applyProgress: Double?

    private let executor = OrganizerExecutor()

    var moveCount: Int { operations.lazy.filter { if case .move = $0.status { return true } else { return false } }.count }
    var unchangedCount: Int { operations.lazy.filter { if case .unchanged = $0.status { return true } else { return false } }.count }
    var conflictCount: Int { operations.lazy.filter { if case .conflict = $0.status { return true } else { return false } }.count }

    func generatePreview(profile: OrganizerProfile, tracks: [Track], rootURL: URL?) {
        guard let rootURL else {
            operations = []
            isPreviewStale = true
            lastError = "Choose a source folder in Settings before organizing."
            return
        }
        lastError = nil
        operations = OrganizerPlanner.plan(tracks: tracks, profile: profile, rootURL: rootURL)
        isPreviewStale = false
    }

    func markStale() {
        isPreviewStale = true
    }

    func apply(library: LibraryStore, profile: OrganizerProfile) async {
        guard !isApplying else { return }
        guard let rootURL = library.rootURL else { return }
        isApplying = true
        applyPhaseLabel = "Preparing…"
        applyProgress = 0
        lastError = nil
        defer {
            isApplying = false
            applyPhaseLabel = nil
            applyProgress = nil
        }

        let ops = operations
        let result = await executor.run(
            operations: ops,
            rootURL: rootURL,
            deleteEmptyOriginals: profile.deleteEmptyOriginals,
            onProgress: { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.updateProgress(progress)
                }
            }
        )

        // Patch LibraryStore: replace each moved track with a copy at its new URL.
        let movedByID = Dictionary(uniqueKeysWithValues: result.moved.map { ($0.trackID, $0.newURL) })
        if !movedByID.isEmpty {
            let updated: [Track] = library.tracks.compactMap { t in
                guard let newURL = movedByID[t.id] else { return nil }
                return Track(
                    id: t.id,
                    url: newURL,
                    title: t.title,
                    artist: t.artist,
                    albumArtist: t.albumArtist,
                    album: t.album,
                    trackNumber: t.trackNumber,
                    duration: t.duration,
                    artwork: t.artwork,
                    fileFormat: AudioFileFormat.classify(newURL) ?? t.fileFormat,
                    sampleRate: t.sampleRate,
                    bitDepth: t.bitDepth,
                    genre: t.genre,
                    year: t.year,
                    isCompilation: t.isCompilation,
                    dateAdded: t.dateAdded
                )
            }
            library.replaceTracks(updated)

            // Update TrackIDStore path keys so the sidecar reflects the new
            // folder layout. PlaylistEntry.trackID values are unaffected —
            // stable UUIDs survive the move without any playlist patching.
            let rootPath = rootURL.path
            let opByTrackID = Dictionary(
                uniqueKeysWithValues: ops.compactMap { op -> (UUID, OrganizerOperation)? in
                    guard case .move = op.status else { return nil }
                    return (op.track.id, op)
                }
            )
            var pathMap: [String: String] = [:]
            for moved in result.moved {
                guard let op = opByTrackID[moved.trackID] else { continue }
                let oldAbs = op.sourceURL.path
                let newAbs = moved.newURL.path
                guard oldAbs.hasPrefix(rootPath), newAbs.hasPrefix(rootPath) else { continue }
                let oldRel = String(oldAbs.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
                let newRel = String(newAbs.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
                pathMap[oldRel] = newRel
            }
            library.trackIDStore.renamePaths(pathMap)
        }

        let movedCount = result.moved.count
        let failedCount = result.failed.count
        let lostCount = result.lostFiles.count

        if lostCount > 0 {
            lastError = "Validation failed: \(lostCount) file\(lostCount == 1 ? " is" : "s are") missing from their destination after move. Check the source folder before re-running."
            lastResultMessage = nil
        } else if failedCount > 0 {
            lastError = "\(failedCount) file\(failedCount == 1 ? "" : "s") could not be moved. Organized \(movedCount)."
            lastResultMessage = nil
        } else {
            lastResultMessage = "Organized \(movedCount) file\(movedCount == 1 ? "" : "s")."
        }

        operations = []
        isPreviewStale = true
    }

    private func updateProgress(_ progress: OrganizerExecutor.Progress) {
        let label: String
        switch progress.phase {
        case .moving: label = "Moving files"
        case .cleaningUp: label = "Cleaning up empty folders"
        case .validating: label = "Validating"
        }
        applyPhaseLabel = progress.total > 0
            ? "\(label) (\(progress.completed)/\(progress.total))"
            : label
        applyProgress = progress.total > 0
            ? Double(progress.completed) / Double(progress.total)
            : 0
    }
}
