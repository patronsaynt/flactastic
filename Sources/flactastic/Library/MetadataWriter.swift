import Foundation
import SwiftUI
import CTagLib
import CTagLibHelper

// MARK: - MetadataWriter

/// Writes tag metadata back to source audio files using the TagLib C API.
/// Declared as an `actor` so writes are serialised (no concurrent writes to
/// the same file) and run on the cooperative thread pool, not the main thread.
///
/// Inject via `.environment(\.metadataWriter, …)` and read with
/// `@Environment(\.metadataWriter)` in SwiftUI views.
actor MetadataWriter {

    // MARK: - Public API

    enum ArtworkChange: Sendable {
        /// Leave the existing artwork untouched.
        case unchanged
        /// Remove any embedded artwork from the file.
        case removed
        /// Replace / set artwork with the supplied image data (JPEG or PNG).
        case updated(Data)
    }

    enum WriteError: LocalizedError {
        case fileNotFound(URL)
        case fileOpenFailed(URL)
        case saveFailed(URL)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "File not found: \(url.lastPathComponent)"
            case .fileOpenFailed(let url):
                return "Could not open \"\(url.lastPathComponent)\" for writing. Check file permissions."
            case .saveFailed(let url):
                return "Failed to save changes to \"\(url.lastPathComponent)\"."
            }
        }
    }

    /// Sentinel passed for `albumArtist` to distinguish "leave alone" from
    /// "clear the tag". `.unchanged` skips the write entirely; `.set(nil)` or
    /// `.set("")` clears the ALBUMARTIST tag; `.set("value")` writes a value.
    enum AlbumArtistChange: Sendable {
        case unchanged
        case set(String?)
    }

    /// Sentinel for the COMPILATION tag. `.unchanged` skips the write;
    /// `.set(true)` writes "1"; `.set(false)` clears the tag.
    enum CompilationChange: Sendable {
        case unchanged
        case set(Bool)
    }

    /// Write text tags and optionally artwork to the file at `track.url`.
    ///
    /// - Returns: An updated `Track` value reflecting the written fields.
    ///   The `id`, `url`, `fileFormat`, `sampleRate`, `bitDepth`, and
    ///   `dateAdded` fields are preserved unchanged.
    func write(
        to track: Track,
        title: String,
        artist: String?,
        album: String?,
        year: Int?,
        genre: String?,
        trackNumber: Int?,
        artworkChange: ArtworkChange = .unchanged,
        albumArtistChange: AlbumArtistChange = .unchanged,
        compilationChange: CompilationChange = .unchanged
    ) throws -> Track {
        let url = track.url

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WriteError.fileNotFound(url)
        }

        guard let file = url.path.withCString({ taglib_file_new($0) }) else {
            throw WriteError.fileOpenFailed(url)
        }
        defer {
            taglib_file_free(file)
            taglib_tag_free_strings()
        }

        guard taglib_file_is_valid(file) != 0 else {
            throw WriteError.fileOpenFailed(url)
        }

        guard let tag = taglib_file_tag(file) else {
            throw WriteError.fileOpenFailed(url)
        }

        // --- Text fields ---
        // Empty string clears a field in TagLib; 0 clears numeric fields.
        title.withCString            { taglib_tag_set_title(tag, $0) }
        (artist      ?? "").withCString { taglib_tag_set_artist(tag, $0) }
        (album       ?? "").withCString { taglib_tag_set_album(tag, $0) }
        (genre       ?? "").withCString { taglib_tag_set_genre(tag, $0) }
        taglib_tag_set_year(tag,  UInt32(max(0, year        ?? 0)))
        taglib_tag_set_track(tag, UInt32(max(0, trackNumber ?? 0)))

        // --- Album artist (via property API / custom helper) ---
        switch albumArtistChange {
        case .unchanged:
            break
        case .set(let value):
            (value ?? "").withCString { taglib_helper_set_album_artist(file, $0) }
        }

        // --- Compilation flag ---
        switch compilationChange {
        case .unchanged:
            break
        case .set(let on):
            taglib_helper_set_compilation(file, on ? 1 : 0)
        }

        // --- Artwork ---
        switch artworkChange {
        case .unchanged:
            break
        case .removed:
            taglib_helper_remove_pictures(file)
        case .updated(let data):
            let mime = mimeType(for: data)
            taglib_helper_remove_pictures(file)
            data.withUnsafeBytes { rawBuf in
                guard let ptr = rawBuf.baseAddress else { return }
                mime.withCString { mimePtr in
                    _ = taglib_helper_set_picture(
                        file,
                        ptr.assumingMemoryBound(to: CChar.self),
                        UInt32(data.count),
                        mimePtr
                    )
                }
            }
        }

        // --- Save ---
        guard taglib_file_save(file) != 0 else {
            throw WriteError.saveFailed(url)
        }

        // --- Build updated Track value ---
        var updated = track
        updated.title       = title.isEmpty ? track.title : title
        updated.artist      = artist.flatMap      { $0.isEmpty ? nil : $0 }
        updated.album       = album.flatMap       { $0.isEmpty ? nil : $0 }
        updated.genre       = genre.flatMap       { $0.isEmpty ? nil : $0 }
        updated.year        = year
        updated.trackNumber = trackNumber
        switch albumArtistChange {
        case .unchanged:        break
        case .set(let value):
            updated.albumArtist = (value?.isEmpty ?? true) ? nil : value
        }
        switch compilationChange {
        case .unchanged:        break
        case .set(let on):      updated.isCompilation = on
        }
        switch artworkChange {
        case .unchanged:   break
        case .removed:     updated.artwork = nil
        case .updated(let d): updated.artwork = d
        }
        return updated
    }

    /// Write a `LYRICS` tag onto the file at `track.url`. TagLib normalizes
    /// the property name to the format-specific frame (Xiph LYRICS / ID3v2
    /// USLT / MP4 ©lyr / WMA WM/Lyrics). Pass `nil` or `""` to clear.
    /// All other tags are left untouched.
    func writeLyrics(to track: Track, lyrics: String?) throws {
        let url = track.url
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WriteError.fileNotFound(url)
        }
        guard let file = url.path.withCString({ taglib_file_new($0) }) else {
            throw WriteError.fileOpenFailed(url)
        }
        defer {
            taglib_file_free(file)
            taglib_tag_free_strings()
        }
        guard taglib_file_is_valid(file) != 0 else {
            throw WriteError.fileOpenFailed(url)
        }
        (lyrics ?? "").withCString { taglib_helper_set_lyrics(file, $0) }
        guard taglib_file_save(file) != 0 else {
            throw WriteError.saveFailed(url)
        }
    }

    /// Read the `LYRICS` tag from the file at `track.url`. Returns nil when
    /// the tag is unset. Useful for honoring user-embedded lyrics without a
    /// network roundtrip.
    func readLyrics(from track: Track) throws -> String? {
        let url = track.url
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let file = url.path.withCString({ taglib_file_new($0) }) else { return nil }
        defer {
            taglib_file_free(file)
            taglib_tag_free_strings()
        }
        guard taglib_file_is_valid(file) != 0 else { return nil }
        guard let cstr = taglib_helper_get_lyrics(file) else { return nil }
        defer { free(cstr) }
        let result = String(cString: cstr)
        return result.isEmpty ? nil : result
    }

    // MARK: - Helpers

    private func mimeType(for data: Data) -> String {
        let header = data.prefix(4)
        if header.starts(with: [0xFF, 0xD8, 0xFF])       { return "image/jpeg" }
        if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png"  }
        return "image/jpeg" // safe default
    }
}

// MARK: - SwiftUI EnvironmentKey

private struct MetadataWriterKey: EnvironmentKey {
    static let defaultValue = MetadataWriter()
}

extension EnvironmentValues {
    var metadataWriter: MetadataWriter {
        get { self[MetadataWriterKey.self] }
        set { self[MetadataWriterKey.self] = newValue }
    }
}
