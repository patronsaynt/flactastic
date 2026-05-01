import Foundation

// Deezer's gw-light returns SHOUTING_SNAKE_CASE keys; we decode straight off
// the wire. Only the fields we actually consume are modelled.

struct DeezerArtistRaw: Decodable, Sendable {
    let ART_ID: String?
    let ART_NAME: String?
    let ART_PICTURE: String?
}

struct DeezerAlbumRaw: Decodable, Sendable {
    let ALB_ID: String?
    let ALB_TITLE: String?
    let ALB_PICTURE: String?
    let ARTISTS: [DeezerArtistRaw]?
    let ORIGINAL_RELEASE_DATE: String?
    let NUMBER_TRACK: String?
    let LABEL_NAME: String?
    let UPC: String?
}

struct DeezerTrackRaw: Decodable, Sendable {
    let SNG_ID: String
    let SNG_TITLE: String
    let VERSION: String?
    let TRACK_NUMBER: String?
    let DISK_NUMBER: String?
    let ARTISTS: [DeezerArtistRaw]?
    let ALB_ID: String?
    let ALB_TITLE: String?
    let ALB_PICTURE: String?
    let DURATION: String?
    let TRACK_TOKEN: String?
    let TRACK_TOKEN_EXPIRE: TimeInterval?
    let FILESIZE_MP3_320: String?
    let FILESIZE_FLAC: String?
    let AVAILABLE_COUNTRIES: AvailableCountries?
    let FALLBACK: Box?

    /// Indirect box so we can declare the recursive `FALLBACK` chain.
    final class Box: Decodable, Sendable {
        let track: DeezerTrackRaw
        init(from decoder: Decoder) throws {
            self.track = try DeezerTrackRaw(from: decoder)
        }
    }

    struct AvailableCountries: Decodable, Sendable {
        let STREAM_ADS: [String]?
    }
}

struct DeezerUserData: Decodable, Sendable {
    let USER: User
    let COUNTRY: String?
    let checkForm: String?

    struct User: Decodable, Sendable {
        let USER_ID: Int
        let OPTIONS: Options?

        struct Options: Decodable, Sendable {
            let license_token: String?
            let web_hq: Bool?
            let web_lossless: Bool?
        }
    }
}

struct DeezerMediaResponse: Decodable, Sendable {
    let data: [Item]?

    struct Item: Decodable, Sendable {
        let media: [Media]?
    }
    struct Media: Decodable, Sendable {
        let sources: [Source]?
    }
    struct Source: Decodable, Sendable {
        let url: String
    }
}

enum DeezerFormat: String, Sendable {
    case MP3_128
    case MP3_320
    case FLAC

    /// Numeric id Deezer uses internally — currently unused (we set `format` by
    /// name in the get_url body) but kept for parity with Lucida.
    var rawID: Int {
        switch self {
        case .MP3_128: return 1
        case .MP3_320: return 3
        case .FLAC:    return 9
        }
    }
}
