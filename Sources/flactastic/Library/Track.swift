import Foundation

struct Track: Sendable, Identifiable, Hashable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String?
    var album: String?
    var trackNumber: Int?
    var duration: TimeInterval?
    var artwork: Data?
    var fileFormat: AudioFileFormat
    var sampleRate: Double?
    var bitDepth: Int?

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        trackNumber: Int? = nil,
        duration: TimeInterval? = nil,
        artwork: Data? = nil,
        fileFormat: AudioFileFormat,
        sampleRate: Double? = nil,
        bitDepth: Int? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNumber = trackNumber
        self.duration = duration
        self.artwork = artwork
        self.fileFormat = fileFormat
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
    }

    static func makeFromURL(_ url: URL) -> Track? {
        guard let format = AudioFileFormat.classify(url) else { return nil }
        let title = url.deletingPathExtension().lastPathComponent
        let album = url.deletingLastPathComponent().lastPathComponent
        return Track(
            url: url,
            title: title,
            album: album.isEmpty ? nil : album,
            fileFormat: format
        )
    }
}

extension Array where Element == Track {
    /// Sort tracks by (album, trackNumber, title) with stable fallbacks for missing metadata.
    func sortedForLibrary() -> [Track] {
        sorted { a, b in
            let albumA = a.album ?? ""
            let albumB = b.album ?? ""
            if albumA != albumB { return albumA.localizedStandardCompare(albumB) == .orderedAscending }
            let tnA = a.trackNumber ?? Int.max
            let tnB = b.trackNumber ?? Int.max
            if tnA != tnB { return tnA < tnB }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
}
