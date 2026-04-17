import Foundation

struct Album: Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String?
    let albumArtist: String?
    let year: Int?
    let genre: String?
    let artwork: Data?
    let tracks: [Track]

    var trackCount: Int { tracks.count }
    var totalDuration: TimeInterval {
        tracks.compactMap(\.duration).reduce(0, +)
    }
}
