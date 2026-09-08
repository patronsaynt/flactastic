import Foundation

// Swift analogues of the types in Resources/lucida/src/types.ts. They describe
// remote items returned by streaming services *before* they become local Track
// rows in LibraryStore — the DownloadCoordinator bridges the two.

struct RemoteArtist: Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let url: URL?
    let pictureURL: URL?
}

struct RemoteCoverArt: Sendable, Hashable {
    let url: URL
    let width: Int?
    let height: Int?
}

struct RemoteAlbumRef: Sendable, Hashable {
    let id: String
    let title: String
    let url: URL?
    let coverArt: [RemoteCoverArt]
    let releaseYear: Int?
    let trackCount: Int?
}

struct RemoteTrack: Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let artists: [RemoteArtist]
    let album: RemoteAlbumRef?
    let trackNumber: Int?
    let discNumber: Int?
    let durationSeconds: Double?
    let coverArt: [RemoteCoverArt]
    /// Service-native URL the user could open in a browser.
    let url: URL?
    /// Service id namespace ("qobuz", "deezer", "soundcloud") — used by
    /// DownloadCoordinator to route back to the right provider for `getStream`.
    let serviceID: String
    /// True when the service indicates lossless / FLAC. Drives the UI badge and
    /// any user warnings before downloading lossy material.
    let isLossless: Bool
}

struct RemoteAlbum: Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let artists: [RemoteArtist]
    let releaseYear: Int?
    let coverArt: [RemoteCoverArt]
    let url: URL?
    let trackCount: Int?
    let tracks: [RemoteTrack]
    let serviceID: String
}

struct RemotePlaylist: Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let creator: String?
    let coverArt: [RemoteCoverArt]
    let url: URL?
    let tracks: [RemoteTrack]
    let serviceID: String
}

struct StreamerSearchResults: Sendable {
    let query: String
    let albums: [RemoteAlbum]
    let tracks: [RemoteTrack]
    let artists: [RemoteArtist]
}

enum RemoteResolveResponse: Sendable {
    case track(RemoteTrack)
    case album(RemoteAlbum)
    case playlist(RemotePlaylist)
    case artist(artist: RemoteArtist, topTracks: [RemoteTrack], albums: [RemoteAlbum])
}

struct StreamerAccount: Sendable {
    let displayName: String?
    let country: String?
    /// True when the account is allowed to fetch lossless streams.
    let lossless: Bool
    /// True when hi-res is available (24-bit).
    let hiRes: Bool
}

extension RemoteCoverArt {
    /// Returns the largest cover (by area), or `nil` when the array is empty.
    static func best(_ arts: [RemoteCoverArt]) -> RemoteCoverArt? {
        arts.max { lhs, rhs in
            let la = (lhs.width ?? 0) * (lhs.height ?? 0)
            let ra = (rhs.width ?? 0) * (rhs.height ?? 0)
            return la < ra
        } ?? arts.first
    }
}
