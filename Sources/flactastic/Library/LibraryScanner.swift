import Foundation
import AVFoundation

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

        let keys: [URLResourceKey] = [.isRegularFileKey, .nameKey]
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
            if let track = Track.makeFromURL(url) {
                tracks.append(track)
            }
        }
        return tracks.sortedForLibrary()
    }

    /// Loads metadata for a single track via AVURLAsset. Returns an updated copy of the track.
    /// Falls back gracefully when fields are missing.
    func loadMetadata(for track: Track) async -> Track {
        let asset = AVURLAsset(url: track.url)
        var updated = track

        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 {
                updated.duration = seconds
            }
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let s = try? await item.load(.stringValue), !s.isEmpty {
                        updated.title = s
                    }
                case .commonKeyArtist:
                    if let s = try? await item.load(.stringValue), !s.isEmpty {
                        updated.artist = s
                    }
                case .commonKeyAlbumName:
                    if let s = try? await item.load(.stringValue), !s.isEmpty {
                        updated.album = s
                    }
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue) {
                        updated.artwork = data
                    }
                default:
                    break
                }
            }
        }

        // Track number lives outside common metadata; check iTunes & ID3 namespaces.
        if let formats = try? await asset.load(.availableMetadataFormats) {
            for format in formats {
                if let items = try? await asset.loadMetadata(for: format) {
                    for item in items {
                        let keyString = (item.key as? String) ?? ""
                        let identifier = item.identifier?.rawValue ?? ""
                        if keyString.contains("trkn") || identifier.contains("trkn") || identifier.contains("TRCK") {
                            if let n = try? await item.load(.numberValue) {
                                updated.trackNumber = n.intValue
                            } else if let s = try? await item.load(.stringValue) {
                                let parts = s.split(separator: "/")
                                if let first = parts.first, let n = Int(first) {
                                    updated.trackNumber = n
                                }
                            }
                        }
                    }
                }
            }
        }

        // Sample rate / bit depth from AVAudioFile (cheap, opens file briefly).
        if let file = try? AVAudioFile(forReading: track.url) {
            updated.sampleRate = file.processingFormat.sampleRate
            // bit depth comes from the underlying stream description if available
            let asbd = file.fileFormat.streamDescription.pointee
            if asbd.mBitsPerChannel > 0 {
                updated.bitDepth = Int(asbd.mBitsPerChannel)
            }
        }

        return updated
    }
}
