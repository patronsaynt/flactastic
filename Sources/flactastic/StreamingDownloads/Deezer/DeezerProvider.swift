import Foundation

/// Native Swift port of `Resources/lucida/src/streamers/deezer/main.ts`. Login
/// is ARL-only (the simpler of the two paths Lucida supports — username/
/// password is omitted because it goes through Deezer's OAuth flow which is
/// brittle and not what users typically have on hand).
actor DeezerProvider: StreamerProvider {
    nonisolated let serviceID = "deezer"
    nonisolated let displayName = "Deezer"
    nonisolated let hostnames = ["deezer.com", "www.deezer.com", "deezer.page.link"]

    private let credentials: CredentialStore
    private var api: DeezerAPI?

    init(credentials: CredentialStore) {
        self.credentials = credentials
    }

    nonisolated var isConfigured: Bool {
        get async {
            !((credentials.read(.deezerARL) ?? "").isEmpty)
        }
    }

    func login() async throws {
        if api != nil { return }
        guard let arl = credentials.read(.deezerARL), !arl.isEmpty else {
            throw StreamerError.notConfigured(service: "Deezer")
        }
        let api = DeezerAPI(arl: arl)
        try await api.login()
        self.api = api
    }

    private func ensureLoggedIn() async throws -> DeezerAPI {
        try await login()
        guard let api else {
            throw StreamerError.notLoggedIn(service: "Deezer")
        }
        return api
    }

    // MARK: - Search

    func search(_ query: String, limit: Int) async throws -> StreamerSearchResults {
        let api = try await ensureLoggedIn()

        struct Bucket<T: Decodable & Sendable>: Decodable, Sendable { let data: [T]? }

        async let albumsResp: Bucket<DeezerAlbumRaw> = api.call(
            method: "search.music",
            params: ["query": query, "start": 0, "nb": limit, "filter": "ALL", "output": "ALBUM"]
        )
        async let tracksResp: Bucket<DeezerTrackRaw> = api.call(
            method: "search.music",
            params: ["query": query, "start": 0, "nb": limit, "filter": "ALL", "output": "TRACK"]
        )
        async let artistsResp: Bucket<DeezerArtistRaw> = api.call(
            method: "search.music",
            params: ["query": query, "start": 0, "nb": limit, "filter": "ALL", "output": "ARTIST"]
        )

        let (albums, tracks, artists) = try await (albumsResp, tracksResp, artistsResp)

        return StreamerSearchResults(
            query: query,
            albums: (albums.data ?? []).map { mapAlbum($0, includeTracks: false) },
            tracks: (tracks.data ?? []).map { mapTrack($0) },
            artists: (artists.data ?? []).compactMap { mapArtist($0) }
        )
    }

    // MARK: - Resolve

    func resolve(_ url: URL) async throws -> RemoteResolveResponse {
        let api = try await ensureLoggedIn()
        let info = try await Self.resolveURL(url, session: URLSession.shared)

        switch info.kind {
        case .track:
            let page: DeezerPageTrack = try await api.call(
                method: "deezer.pageTrack",
                params: ["sng_id": info.id]
            )
            return .track(mapTrack(page.DATA))
        case .album:
            let page: DeezerPageAlbum = try await api.call(
                method: "deezer.pageAlbum",
                params: ["alb_id": info.id, "lang": "en"]
            )
            return .album(mapAlbum(page.DATA, songs: page.SONGS.data))
        case .artist:
            let page: DeezerPageArtist = try await api.call(
                method: "deezer.pageArtist",
                params: ["art_id": info.id, "lang": "en"]
            )
            let artist = mapArtist(page.DATA) ?? RemoteArtist(id: info.id, name: "Unknown", url: nil, pictureURL: nil)
            let topTracks = (page.TOP?.data ?? []).map { mapTrack($0) }
            let albums = (page.ALBUMS?.data ?? []).map { mapAlbum($0, includeTracks: false) }
            return .artist(artist: artist, topTracks: topTracks, albums: albums)
        case .playlist:
            let metaPage: DeezerPagePlaylist = try await api.call(
                method: "deezer.pagePlaylist",
                params: ["playlist_id": info.id]
            )
            struct SongsPayload: Decodable, Sendable { let data: [DeezerTrackRaw]? }
            let songs: SongsPayload = try await api.call(
                method: "playlist.getSongs",
                params: ["playlist_id": info.id, "nb": 9999, "start": 0]
            )
            let tracks = (songs.data ?? []).map { mapTrack($0) }
            let coverURL = metaPage.DATA.PLAYLIST_PICTURE.map { Self.coverArtwork(picture: $0, kind: "playlist") } ?? []
            return .playlist(RemotePlaylist(
                id: metaPage.DATA.PLAYLIST_ID,
                title: metaPage.DATA.TITLE,
                creator: nil,
                coverArt: coverURL,
                url: URL(string: "https://www.deezer.com/playlist/\(metaPage.DATA.PLAYLIST_ID)"),
                tracks: tracks,
                serviceID: serviceID
            ))
        }
    }

    // MARK: - Stream

    func getStream(for track: RemoteTrack) async throws -> DownloadStream {
        let api = try await ensureLoggedIn()

        // We need the full track row to pick the best available format and
        // grab the TRACK_TOKEN + AVAILABLE_COUNTRIES. The provider's
        // `RemoteTrack.id` is `SNG_ID`.
        let page: DeezerPageTrack = try await api.call(
            method: "deezer.pageTrack",
            params: ["sng_id": track.id]
        )
        var raw = page.DATA
        if let fb = raw.FALLBACK?.track {
            // Lucida prefers the FALLBACK row when present (the original is
            // often country-restricted).
            raw = fb
        }

        // Country gate.
        let countries = raw.AVAILABLE_COUNTRIES?.STREAM_ADS ?? []
        let userCountry = await api.country
        if let userCountry, !countries.isEmpty, !countries.contains(userCountry) {
            throw StreamerError.unavailable("Deezer track not available in \(userCountry).")
        }

        // Pick best available format.
        let formats = await api.availableFormats
        let format: DeezerFormat
        if (raw.FILESIZE_FLAC.flatMap(Int.init) ?? 0) > 0 && formats.contains(.FLAC) {
            format = .FLAC
        } else if (raw.FILESIZE_MP3_320.flatMap(Int.init) ?? 0) > 0 && formats.contains(.MP3_320) {
            format = .MP3_320
        } else {
            format = .MP3_128
        }

        // Refresh token if expired.
        var trackToken = raw.TRACK_TOKEN ?? ""
        let now = Date().timeIntervalSince1970
        if let expiry = raw.TRACK_TOKEN_EXPIRE, now >= expiry {
            trackToken = try await api.refreshTrackToken(trackID: raw.SNG_ID)
        }
        if trackToken.isEmpty {
            throw StreamerError.unavailable("Deezer did not return a track token.")
        }

        let cdnURL = try await api.getStreamURL(trackToken: trackToken, format: format)
        let (asyncBytes, response) = try await api.downloadCDN(url: cdnURL)
        let size = response.expectedContentLength > 0 ? Int64(response.expectedContentLength) : nil

        // Wrap in our chunked Data stream first, then through the Blowfish-CBC
        // stripe decryptor.
        let plainStream = DownloadStream.from(
            urlSessionBytes: asyncBytes,
            mimeType: format == .FLAC ? "audio/flac" : "audio/mpeg",
            sizeBytes: size,
            suggestedExtension: format == .FLAC ? "flac" : "mp3"
        )
        let key = DeezerCrypto.deriveKey(forTrackID: raw.SNG_ID)
        let decrypted = DeezerCrypto.decryptingStream(upstream: plainStream.bytes, key: key)
        return DownloadStream(
            bytes: decrypted,
            mimeType: plainStream.mimeType,
            sizeBytes: plainStream.sizeBytes,
            suggestedExtension: plainStream.suggestedExtension
        )
    }

    // MARK: - Account

    func accountInfo() async throws -> StreamerAccount {
        let api = try await ensureLoggedIn()
        let formats = await api.availableFormats
        return StreamerAccount(
            displayName: nil,
            country: await api.country,
            lossless: formats.contains(.FLAC),
            hiRes: false
        )
    }

    // MARK: - URL parsing (page.link unshorten + path match)

    private struct URLInfo: Sendable {
        enum Kind: Sendable { case track, album, artist, playlist }
        let kind: Kind
        let id: String
    }

    private static func resolveURL(_ url: URL, session: URLSession) async throws -> URLInfo {
        var working = url
        if (url.host ?? "").lowercased() == "deezer.page.link" {
            working = try await unshorten(url, session: session)
        }
        let path = working.path
        // /<locale>?/<kind>/<id>(/?)
        let pattern = "^/(?:[a-z]{2}/)?(track|album|artist|playlist)/(\\d+)/?$"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = regex.firstMatch(in: path, range: range),
              let kindRange = Range(match.range(at: 1), in: path),
              let idRange = Range(match.range(at: 2), in: path) else {
            throw StreamerError.unsupportedURL(working)
        }
        let kindStr = String(path[kindRange])
        let id = String(path[idRange])
        let kind: URLInfo.Kind
        switch kindStr {
        case "track":    kind = .track
        case "album":    kind = .album
        case "artist":   kind = .artist
        case "playlist": kind = .playlist
        default:         throw StreamerError.unsupportedURL(working)
        }
        return URLInfo(kind: kind, id: id)
    }

    private static func unshorten(_ url: URL, session: URLSession) async throws -> URL {
        // We want a 302, not the redirect-followed final response. Use a
        // bespoke session config that returns the redirect.
        let config = URLSessionConfiguration.ephemeral
        let local = URLSession(configuration: config, delegate: NoFollowRedirect(), delegateQueue: nil)
        defer { local.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (_, response) = try await local.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 302,
              let location = http.value(forHTTPHeaderField: "Location"),
              let target = URL(string: location) else {
            throw StreamerError.unsupportedURL(url)
        }
        return target
    }

    private final class NoFollowRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    // MARK: - Mapping

    private static let coverSizes = [256, 512, 1024, 1200]

    private static func coverArtwork(picture: String, kind: String) -> [RemoteCoverArt] {
        coverSizes.compactMap { size in
            guard let url = URL(
                string: "https://e-cdns-images.dzcdn.net/images/\(kind)/\(picture)/\(size)x\(size)-000000-80-0-0.jpg"
            ) else { return nil }
            return RemoteCoverArt(url: url, width: size, height: size)
        }
    }

    private nonisolated func mapArtist(_ raw: DeezerArtistRaw) -> RemoteArtist? {
        guard let id = raw.ART_ID, let name = raw.ART_NAME else { return nil }
        let pictureURL = raw.ART_PICTURE.flatMap {
            URL(string: "https://e-cdns-images.dzcdn.net/images/artist/\($0)/500x500-000000-80-0-0.jpg")
        }
        return RemoteArtist(
            id: id,
            name: name,
            url: URL(string: "https://www.deezer.com/artist/\(id)"),
            pictureURL: pictureURL
        )
    }

    private nonisolated func mapAlbum(_ raw: DeezerAlbumRaw, includeTracks: Bool = false) -> RemoteAlbum {
        let songs: [DeezerTrackRaw] = []
        return mapAlbum(raw, songs: includeTracks ? songs : [])
    }

    private nonisolated func mapAlbum(_ raw: DeezerAlbumRaw, songs: [DeezerTrackRaw]) -> RemoteAlbum {
        let id = raw.ALB_ID ?? ""
        let title = raw.ALB_TITLE ?? "Unknown Album"
        let artists = (raw.ARTISTS ?? []).compactMap { mapArtist($0) }
        let cover = raw.ALB_PICTURE.map { Self.coverArtwork(picture: $0, kind: "cover") } ?? []
        let releaseYear: Int? = raw.ORIGINAL_RELEASE_DATE.flatMap { Self.year(fromISODate: $0) }
        let albumRef = RemoteAlbumRef(
            id: id,
            title: title,
            url: URL(string: "https://www.deezer.com/album/\(id)"),
            coverArt: cover,
            releaseYear: releaseYear,
            trackCount: raw.NUMBER_TRACK.flatMap(Int.init)
        )
        let tracks = songs.map { mapTrack($0, albumOverride: albumRef, fallbackArtists: artists) }
        return RemoteAlbum(
            id: id,
            title: title,
            artists: artists,
            releaseYear: releaseYear,
            coverArt: cover,
            url: URL(string: "https://www.deezer.com/album/\(id)"),
            trackCount: raw.NUMBER_TRACK.flatMap(Int.init),
            tracks: tracks,
            serviceID: serviceID
        )
    }

    private nonisolated func mapTrack(
        _ raw: DeezerTrackRaw,
        albumOverride: RemoteAlbumRef? = nil,
        fallbackArtists: [RemoteArtist] = []
    ) -> RemoteTrack {
        let title = raw.VERSION.flatMap { v in v.isEmpty ? nil : "\(raw.SNG_TITLE) \(v)" } ?? raw.SNG_TITLE
        let artists = (raw.ARTISTS ?? []).compactMap { mapArtist($0) }
        let resolvedArtists = artists.isEmpty ? fallbackArtists : artists
        let cover = raw.ALB_PICTURE.map { Self.coverArtwork(picture: $0, kind: "cover") } ?? []
        let albumRef: RemoteAlbumRef?
        if let override = albumOverride { albumRef = override }
        else if let albID = raw.ALB_ID, !albID.isEmpty {
            albumRef = RemoteAlbumRef(
                id: albID,
                title: raw.ALB_TITLE ?? "Unknown Album",
                url: URL(string: "https://www.deezer.com/album/\(albID)"),
                coverArt: cover,
                releaseYear: nil,
                trackCount: nil
            )
        } else { albumRef = nil }
        let losslessAvailable = (raw.FILESIZE_FLAC.flatMap(Int.init) ?? 0) > 0
        return RemoteTrack(
            id: raw.SNG_ID,
            title: title,
            artists: resolvedArtists,
            album: albumRef,
            trackNumber: raw.TRACK_NUMBER.flatMap(Int.init),
            discNumber: raw.DISK_NUMBER.flatMap(Int.init),
            durationSeconds: raw.DURATION.flatMap(Double.init),
            coverArt: cover,
            url: URL(string: "https://www.deezer.com/track/\(raw.SNG_ID)"),
            serviceID: serviceID,
            isLossless: losslessAvailable
        )
    }

    private static func year(fromISODate: String) -> Int? {
        // Deezer dates are "YYYY-MM-DD". Pull off the leading year cheaply.
        let head = fromISODate.prefix(4)
        return Int(head)
    }
}

// Deezer "page" JSON shapes — used only at resolve-time.

private struct DeezerPageTrack: Decodable, Sendable {
    let DATA: DeezerTrackRaw
}

private struct DeezerPageAlbum: Decodable, Sendable {
    let DATA: DeezerAlbumRaw
    let SONGS: Songs
    struct Songs: Decodable, Sendable { let data: [DeezerTrackRaw] }
}

private struct DeezerPageArtist: Decodable, Sendable {
    let DATA: DeezerArtistRaw
    let TOP: Top?
    let ALBUMS: Albums?
    struct Top: Decodable, Sendable { let data: [DeezerTrackRaw]? }
    struct Albums: Decodable, Sendable { let data: [DeezerAlbumRaw]? }
}

private struct DeezerPagePlaylist: Decodable, Sendable {
    let DATA: PlaylistMeta
    struct PlaylistMeta: Decodable, Sendable {
        let PLAYLIST_ID: String
        let TITLE: String
        let PLAYLIST_PICTURE: String?
    }
}
