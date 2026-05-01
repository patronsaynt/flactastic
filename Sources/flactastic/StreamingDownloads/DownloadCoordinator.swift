import Foundation
import Observation
import SwiftUI

/// Orchestrates: provider.getStream → write to temp → tag → move into library
/// → trigger LibraryStore rescan. Owns a serial queue per service so a single
/// flaky provider can't block another.
@Observable
@MainActor
final class DownloadCoordinator {
    enum JobStatus: Sendable, Equatable {
        case queued
        case downloading(receivedBytes: Int64, totalBytes: Int64?)
        case tagging
        case finishing
        case completed(URL)
        case failed(String)

        var isTerminal: Bool {
            switch self {
            case .completed, .failed: return true
            default: return false
            }
        }
    }

    struct Job: Identifiable, Sendable {
        let id: UUID
        let track: RemoteTrack
        var status: JobStatus
    }

    private(set) var jobs: [Job] = []

    private let registry: StreamerRegistry
    private let library: LibraryStore
    private let writer: MetadataWriter
    private let urlSession: URLSession

    init(
        registry: StreamerRegistry,
        library: LibraryStore,
        writer: MetadataWriter,
        urlSession: URLSession = .shared
    ) {
        self.registry = registry
        self.library = library
        self.writer = writer
        self.urlSession = urlSession
    }

    // MARK: - Public API

    func enqueue(_ track: RemoteTrack) {
        let job = Job(id: UUID(), track: track, status: .queued)
        jobs.append(job)
        Task { await run(jobID: job.id) }
    }

    func enqueue(_ tracks: [RemoteTrack]) {
        for t in tracks { enqueue(t) }
    }

    func clearCompleted() {
        jobs.removeAll { $0.status.isTerminal }
    }

    // MARK: - Job pipeline

    private func update(_ id: UUID, _ status: JobStatus) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].status = status
    }

    private func run(jobID: UUID) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        let track = job.track

        guard let provider = registry.provider(serviceID: track.serviceID) else {
            update(jobID, .failed("Provider \"\(track.serviceID)\" no longer registered."))
            return
        }
        guard let rootURL = library.rootURL else {
            update(jobID, .failed("No music folder selected. Open Settings → Config first."))
            return
        }

        do {
            update(jobID, .downloading(receivedBytes: 0, totalBytes: nil))
            let stream = try await provider.getStream(for: track)
            update(jobID, .downloading(receivedBytes: 0, totalBytes: stream.sizeBytes))

            // Stream to a temp file. We can't write tags into the stream
            // directly because TagLib needs random access; tag once the file
            // is fully on disk.
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("flactastic-dl-\(jobID.uuidString).\(stream.suggestedExtension)")
            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: tempURL)
            defer { try? handle.close() }

            var received: Int64 = 0
            for try await chunk in stream.bytes {
                try handle.write(contentsOf: chunk)
                received += Int64(chunk.count)
                update(jobID, .downloading(receivedBytes: received, totalBytes: stream.sizeBytes))
            }
            try handle.close()

            // --- Tag the file using metadata we already have from the provider.
            update(jobID, .tagging)
            let artworkData = await Self.fetchArtwork(track: track, session: urlSession)
            let format = AudioFileFormat.classify(tempURL) ?? .flac
            let stagedTrack = Track(
                url: tempURL,
                title: track.title,
                artist: track.artists.first?.name,
                albumArtist: track.album?.title.isEmpty == false ? track.artists.first?.name : nil,
                album: track.album?.title,
                trackNumber: track.trackNumber,
                duration: track.durationSeconds,
                artwork: artworkData,
                fileFormat: format,
                year: track.album?.releaseYear,
                isCompilation: false
            )

            _ = try await writer.write(
                to: stagedTrack,
                title: track.title,
                artist: track.artists.first?.name,
                album: track.album?.title,
                year: track.album?.releaseYear,
                genre: nil,
                trackNumber: track.trackNumber,
                artworkChange: artworkData.map { .updated($0) } ?? .unchanged,
                albumArtistChange: .set(track.artists.first?.name),
                compilationChange: .unchanged
            )

            // --- Move into library at Artist/Album/NN - Title.ext.
            update(jobID, .finishing)
            let finalURL = try Self.finalDestination(
                rootURL: rootURL,
                track: track,
                ext: stream.suggestedExtension
            )
            try FileManager.default.createDirectory(
                at: finalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // If a file already exists at the destination, append a UUID
            // suffix rather than overwriting the user's existing copy.
            var dest = finalURL
            if FileManager.default.fileExists(atPath: dest.path) {
                let stem = finalURL.deletingPathExtension().lastPathComponent
                let parent = finalURL.deletingLastPathComponent()
                dest = parent.appendingPathComponent("\(stem) (\(UUID().uuidString.prefix(8))).\(stream.suggestedExtension)")
            }
            try FileManager.default.moveItem(at: tempURL, to: dest)

            update(jobID, .completed(dest))
            library.refreshLibrary()
        } catch {
            update(jobID, .failed((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
    }

    // MARK: - Helpers

    private static func fetchArtwork(track: RemoteTrack, session: URLSession) async -> Data? {
        let arts = !track.coverArt.isEmpty ? track.coverArt : (track.album?.coverArt ?? [])
        guard let best = RemoteCoverArt.best(arts) else { return nil }
        do {
            let (data, _) = try await session.data(from: best.url)
            return data
        } catch {
            return nil
        }
    }

    /// Builds <root>/<albumArtist>/<album>/NN - <title>.<ext>, with each path
    /// component sanitised against macOS-illegal characters.
    private static func finalDestination(rootURL: URL, track: RemoteTrack, ext: String) throws -> URL {
        let artistDir = sanitize(track.artists.first?.name ?? "Unknown Artist")
        let albumDir = sanitize(track.album?.title ?? "Singles")
        let trackPrefix = track.trackNumber.map { String(format: "%02d - ", $0) } ?? ""
        let filename = sanitize(trackPrefix + track.title) + "." + ext
        return rootURL
            .appendingPathComponent(artistDir)
            .appendingPathComponent(albumDir)
            .appendingPathComponent(filename)
    }

    private static func sanitize(_ raw: String) -> String {
        // ":" and "/" are the two characters macOS Finder forbids in path
        // components. Everything else (including emoji) survives.
        let bad: Set<Character> = ["/", ":"]
        let cleaned = String(raw.map { bad.contains($0) ? "-" : $0 })
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
