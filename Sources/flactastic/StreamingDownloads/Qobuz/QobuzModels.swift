import Foundation

// Raw JSON shapes returned by Qobuz's `api.json/0.2/...` endpoints. Only the
// fields we actually consume are decoded; everything else is ignored. Mirrors
// the TypeScript types in Resources/lucida/src/streamers/qobuz/parse.ts.

struct QobuzImage: Decodable, Sendable {
    let thumbnail: String?
    let small: String?
    let large: String?
}

struct QobuzArtistRaw: Decodable, Sendable {
    let id: Int
    let name: String
    let picture: String?
    let image: QobuzArtistImage?

    struct QobuzArtistImage: Decodable, Sendable {
        let small: String?
        let medium: String?
        let large: String?
    }
}

struct QobuzAlbumRaw: Decodable, Sendable {
    let title: String
    let version: String?
    let id: String
    let url: String?
    let image: QobuzImage
    let tracks_count: Int?
    let released_at: TimeInterval?
    let release_date_original: String?
    let artist: QobuzArtistRaw?
    let artists: [QobuzArtistRaw]?
    let tracks: QobuzAlbumTracks?
    let upc: String?

    struct QobuzAlbumTracks: Decodable, Sendable {
        let items: [QobuzTrackRaw]?
    }
}

struct QobuzTrackRaw: Decodable, Sendable {
    let id: Int
    let title: String
    let version: String?
    let duration: Int?
    let track_number: Int?
    let media_number: Int?
    let parental_warning: Bool?
    let isrc: String?
    let performer: QobuzArtistRaw?
    let album: QobuzAlbumRaw?
}

struct QobuzPlaylistRaw: Decodable, Sendable {
    let id: Int
    let name: String
    let tracks_count: Int?
    let images: [String]?
    let owner: QobuzPlaylistOwner?
    let tracks: QobuzPlaylistTracks?

    struct QobuzPlaylistOwner: Decodable, Sendable {
        let id: Int?
        let name: String?
    }

    struct QobuzPlaylistTracks: Decodable, Sendable {
        let items: [QobuzTrackRaw]?
        let total: Int?
    }
}

struct QobuzSearchResponse: Decodable, Sendable {
    let query: String?
    let albums: AlbumBucket?
    let tracks: TrackBucket?
    let artists: ArtistBucket?

    struct AlbumBucket: Decodable, Sendable { let items: [QobuzAlbumRaw]? }
    struct TrackBucket: Decodable, Sendable { let items: [QobuzTrackRaw]? }
    struct ArtistBucket: Decodable, Sendable { let items: [QobuzArtistRaw]? }
}

struct QobuzLoginResponse: Decodable, Sendable {
    let user_auth_token: String
    let user: QobuzUser

    struct QobuzUser: Decodable, Sendable {
        let id: Int?
        let display_name: String?
        let country: String?
        let credential: QobuzCredential?
        let subscription: QobuzSubscription?

        struct QobuzCredential: Decodable, Sendable {
            let parameters: QobuzCredentialParams?

            struct QobuzCredentialParams: Decodable, Sendable {
                let lossy_streaming: Bool?
                let lossless_streaming: Bool?
                let hires_streaming: Bool?
            }
        }

        struct QobuzSubscription: Decodable, Sendable {
            let offer: String?
        }
    }
}

struct QobuzFileURLResponse: Decodable, Sendable {
    let url: String
    let mime_type: String?
    let format_id: Int?
    let bit_depth: Int?
    let sampling_rate: Double?
    let sample: Bool?
}
