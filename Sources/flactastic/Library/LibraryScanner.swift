import Foundation
import AVFoundation
import CTagLib
import CTagLibHelper

actor LibraryScanner {
    enum ScanError: Error {
        case rootNotFound
        case rootNotReadable
    }

    func scan(root: URL) throws -> [Track] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw ScanError.rootNotFound
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .nameKey,
            .addedToDirectoryDateKey,
            .creationDateKey,
            .contentModificationDateKey,
        ]
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ScanError.rootNotReadable
        }

        var tracks: [Track] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile != true { continue }
            if var track = Track.makeFromURL(url) {
                // Prefer APFS "added to directory" (the true "date added" a
                // user expects in a library view), fall back to creation, then
                // modification. Missing timestamps are tolerated — sorts push
                // them to the end.
                track.dateAdded = values?.addedToDirectoryDate
                    ?? values?.creationDate
                    ?? values?.contentModificationDate
                tracks.append(track)
            }
        }
        return tracks.sortedForLibrary()
    }

    /// Loads metadata for a single track. Tag fields (title/artist/album/etc.) are
    /// read via TagLib — the same library used for writes — so edits always round-trip
    /// correctly without relying on AVFoundation's metadata cache. Audio format
    /// properties (duration, sample rate, bit depth) still come from AVFoundation.
    func loadMetadata(for track: Track) async -> Track {
        var updated = track

        // --- Tag fields via TagLib (bypasses AVFoundation metadata cache) ---
        track.url.path.withCString { pathPtr in
            guard let file = taglib_file_new(pathPtr) else { return }
            defer {
                taglib_file_free(file)
                taglib_tag_free_strings()
            }
            guard taglib_file_is_valid(file) != 0,
                  let tag = taglib_file_tag(file) else { return }

            if let ptr = taglib_tag_title(tag), ptr.pointee != 0 {
                updated.title = String(cString: ptr)
            }
            if let ptr = taglib_tag_artist(tag), ptr.pointee != 0 {
                updated.artist = String(cString: ptr)
            }
            if let ptr = taglib_tag_album(tag), ptr.pointee != 0 {
                updated.album = String(cString: ptr)
            }
            if let ptr = taglib_tag_genre(tag), ptr.pointee != 0 {
                updated.genre = String(cString: ptr)
            }
            let year = taglib_tag_year(tag)
            if year > 0 { updated.year = Int(year) }
            let track = taglib_tag_track(tag)
            if track > 0 { updated.trackNumber = Int(track) }

            var picSize: UInt32 = 0
            if let picBytes = taglib_helper_read_picture(file, &picSize), picSize > 0 {
                updated.artwork = Data(bytes: picBytes, count: Int(picSize))
                free(picBytes)
            }
        }

        // --- Audio format properties via AVFoundation ---
        let asset = AVURLAsset(url: track.url)
        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 {
                updated.duration = seconds
            }
        }

        if let file = try? AVAudioFile(forReading: track.url) {
            updated.sampleRate = file.processingFormat.sampleRate
            let asbd = file.fileFormat.streamDescription.pointee
            if asbd.mBitsPerChannel > 0 {
                updated.bitDepth = Int(asbd.mBitsPerChannel)
            }
        }

        return updated
    }
}
