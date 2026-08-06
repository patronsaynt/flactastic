import Foundation

struct Album: Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String?
    let albumArtist: String?
    let year: Int?
    let genre: String?
    let secondaryGenres: [String]
    let artwork: Data?
    let tracks: [Track]

    var trackCount: Int { tracks.count }
    var totalDuration: TimeInterval {
        tracks.compactMap(\.duration).reduce(0, +)
    }
    /// True when any track in the album carries the COMPILATION tag. The flag
    /// is per-track in the file format, so users editing through FLACtastic's
    /// album editor get an all-or-nothing toggle that writes every track.
    var isCompilation: Bool {
        tracks.contains(where: \.isCompilation)
    }
}
