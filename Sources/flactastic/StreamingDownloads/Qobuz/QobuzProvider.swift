import Foundation
import CryptoKit

/// Native Swift port of `Resources/lucida/src/streamers/qobuz/main.ts`. Pure
/// HTTPS — no decryption, no ffmpeg. The user supplies app_id + app_secret +
/// account credentials in Settings; we cache `user_auth_token` in the keychain
/// after first login.
actor QobuzProvider: StreamerProvider {
    nonisolated let serviceID = "qobuz"
    nonisolated let displayName = "Qobuz"
    nonisolated let hostnames = [
        "play.qobuz.com",
        "open.qobuz.com",
        "www.qobuz.com",
        "qobuz.com"
    ]

    private var api: QobuzAPI
    private let credentials: CredentialStore
    private var loggedIn: Bool

    init(credentials: CredentialStore) {
        self.credentials = credentials
        let appID = credentials.read(.qobuzAppID) ?? ""
        let appSecret = credentials.read(.qobuzAppSecret) ?? ""
        let token = credentials.read(.qobuzUserAuthToken)
        self.api = QobuzAPI(appID: appID, appSecret: appSecret, userAuthToken: token)
        self.loggedIn = token != nil
    }

    nonisolated var isConfigured: Bool {
        get async {
            let appID = credentials.read(.qobuzAppID) ?? ""
            let appSecret = credentials.read(.qobuzAppSecret) ?? ""
            let username = credentials.read(.qobuzUsername) ?? ""
            let password = credentials.read(.qobuzPassword) ?? ""
            let cachedToken = credentials.read(.qobuzUserAuthToken) ?? ""
            return !appID.isEmpty && !appSecret.isEmpty
                && (!cachedToken.isEmpty || (!username.isEmpty && !password.isEmpty))
        }
    }

    func login() async throws {
        if loggedIn, api.userAuthToken != nil { return }

        let appID = credentials.read(.qobuzAppID) ?? ""
        let appSecret = credentials.read(.qobuzAppSecret) ?? ""
        guard !appID.isEmpty, !appSecret.isEmpty else {
            throw StreamerError.notConfigured(service: "Qobuz")
        }
        // Rebuild API in case the user just edited credentials.
        api = QobuzAPI(appID: appID, appSecret: appSecret, userAuthToken: credentials.read(.qobuzUserAuthToken))

        if api.userAuthToken == nil {
            let username = credentials.read(.qobuzUsername) ?? ""
            let password = credentials.read(.qobuzPassword) ?? ""
            guard !username.isEmpty, !password.isEmpty else {
                throw StreamerError.notConfigured(service: "Qobuz")
            }
            // Qobuz requires md5(password). The signature algorithm later then
            // hashes the *whole* parameter set including this md5, so we pass
            // the hex digest as the value of `password`.
            let pwHash = Insecure.MD5.hash(data: Data(password.utf8))
                .map { String(format: "%02x", $0) }.joined()
            let params: [String: String] = [
                "username": username,
                "password": pwHash,
                "extra": "partner",
                "app_id": appID
            ]
            let resp: QobuzLoginResponse = try await api.getSigned("user/login", params: params)
            api.userAuthToken = resp.user_auth_token
            credentials.write(resp.user_auth_token, for: .qobuzUserAuthToken)
        }
        loggedIn = true
    }

    // MARK: - Search

    func search(_ query: String, limit: Int) async throws -> StreamerSearchResults {
        try await login()
        let resp: QobuzSearchResponse = try await api.get("catalog/search", params: [
            "query": query,
            "limit": String(limit),
            "app_id": api.appID
        ])
        return StreamerSearchResults(
            query: resp.query ?? query,
            albums: (resp.albums?.items ?? []).map { mapAlbum($0, includeTracks: false) },
            tracks: (resp.tracks?.items ?? []).map { mapTrack($0) },
            artists: (resp.artists?.items ?? []).map { mapArtist($0) }
        )
    }

    // MARK: - Resolve

    func resolve(_ url: URL) async throws -> RemoteResolveResponse {
        try await login()
        let parts = try Self.parseURL(url)
        switch parts.kind {
        case .track:
            let raw: QobuzTrackRaw = try await api.get("track/get", params: [
                "track_id": parts.id,
                "app_id": api.appID
            ])
            return .track(mapTrack(raw))
        case .album:
            let raw: QobuzAlbumRaw = try await api.get("album/get", params: [
                "album_id": parts.id,
                "extra": "albumsFromSameArtist,focusAll",
                "app_id": api.appID
            ])
            return .album(mapAlbum(raw, includeTracks: true))
        case .artist:
            // Lucida returns artist metadata with appearance albums. We pull a
            // basic profile here — `topTracks` and `albums` arrays come back
            // empty for now (the search picker is a more useful path for
            // browsing an artist anyway).
            let raw: QobuzArtistRaw = try await api.get("artist/get", params: [
                "artist_id": parts.id,
                "app_id": api.appID
            ])
            return .artist(artist: mapArtist(raw), topTracks: [], albums: [])
        case .playlist:
            let raw: QobuzPlaylistRaw = try await api.get("playlist/get", params: [
                "playlist_id": parts.id,
                "extra": "tracks,getSimilarPlaylists",
                "offset": "0",
                "limit": "1000",
                "app_id": api.appID
            ])
            return .playlist(mapPlaylist(raw))
        }
    }

    // MARK: - Stream

    func getStream(for track: RemoteTrack) async throws -> DownloadStream {
        try await login()
        // Qobuz format ids: 5=MP3, 6=FLAC 16-bit, 7=FLAC 24-bit ≤96kHz, 27=FLAC
        // 24-bit ≤192kHz (hi-res). We always ask for 27; the API silently
        // downgrades to whatever the user's subscription / track allows.
        let params: [String: String] = [
            "track_id": track.id,
            "format_id": "27",
            "intent": "stream",
            "sample": "false",
            "app_id": api.appID,
            "user_auth_token": api.userAuthToken ?? ""
        ]
        let resp: QobuzFileURLResponse = try await api.getSigned("track/getFileUrl", params: params)
        if resp.sample == true {
            throw StreamerError.unavailable("Could not get a non-sample file from Qobuz. The track may be purchase-only.")
        }
        guard let cdnURL = URL(string: resp.url) else {
            throw StreamerError.decoding("Qobuz returned an invalid CDN URL: \(resp.url)")
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: cdnURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw StreamerError.http(
                status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                body: nil
            )
        }
        let mime = resp.mime_type ?? http.mimeType ?? "application/octet-stream"
        let suggestedExt = Self.extensionFor(mime: mime, formatID: resp.format_id)
        let size = http.expectedContentLength > 0 ? Int64(http.expectedContentLength) : nil

        return DownloadStream.from(
            urlSessionBytes: asyncBytes,
            mimeType: mime,
            sizeBytes: size,
            suggestedExtension: suggestedExt
        )
    }

    // MARK: - Account

    func accountInfo() async throws -> StreamerAccount {
        try await login()
        let resp: QobuzLoginResponse = try await api.getSigned("user/login", params: [
            "extra": "partner",
            "device_manufacturer_id": "undefined",
            "app_id": api.appID
        ])
        let params = resp.user.credential?.parameters
        let lossless = params?.lossless_streaming ?? false
        let hires = params?.hires_streaming ?? false
        return StreamerAccount(
            displayName: resp.user.display_name,
            country: resp.user.country,
            lossless: lossless,
            hiRes: hires
        )
    }

    // MARK: - URL parsing

    private struct URLParts: Sendable {
        enum Kind: Sendable { case track, album, artist, playlist }
        let kind: Kind
        let id: String
    }

    /// Mirrors `Resources/lucida/src/streamers/qobuz/main.ts:254-289`.
    /// Recognises three URL shapes:
    ///   - https://(www.)qobuz.com/<locale>/(album|track|interpreter|playlists)/<slug>/<id>
    ///   - https://(play|open).qobuz.com/(track|album|artist|playlist)/<id>
    ///   - https://open.qobuz.com/playlist/<id>
    private static func parseURL(_ url: URL) throws -> URLParts {
        let host = (url.host ?? "").lowercased()
        let path = url.path
        let qstripped = path.split(separator: "?").first.map(String.init) ?? path

        if host == "qobuz.com" || host == "www.qobuz.com" {
            // /us-en/album/foo-bar/<id> | /us-en/track/foo-bar/<id> | /us-en/interpreter/foo/<id>
            let comps = qstripped.split(separator: "/").map(String.init)
            // [locale, kind, slug, id]
            guard comps.count >= 4 else { throw StreamerError.unsupportedURL(url) }
            let kindStr = comps[1]
            let id = comps.last!
            switch kindStr {
            case "album":       return URLParts(kind: .album, id: id)
            case "track":       return URLParts(kind: .track, id: id)
            case "interpreter": return URLParts(kind: .artist, id: id)
            case "playlists":   return URLParts(kind: .playlist, id: id)
            default: throw StreamerError.unsupportedURL(url)
            }
        }

        if host == "play.qobuz.com" || host == "open.qobuz.com" {
            // /<kind>/<id>
            let comps = qstripped.split(separator: "/").map(String.init)
            guard comps.count >= 2 else { throw StreamerError.unsupportedURL(url) }
            let kindStr = comps[0]
            let id = comps[1]
            switch kindStr {
            case "track":    return URLParts(kind: .track, id: id)
            case "album":    return URLParts(kind: .album, id: id)
            case "artist":   return URLParts(kind: .artist, id: id)
            case "playlist": return URLParts(kind: .playlist, id: id)
            default: throw StreamerError.unsupportedURL(url)
            }
        }

        throw StreamerError.unsupportedURL(url)
    }

    // MARK: - Mapping (raw JSON → RemoteTrack/Album/Artist)

    private nonisolated func mapArtist(_ raw: QobuzArtistRaw) -> RemoteArtist {
        let pic = raw.picture
            ?? raw.image?.large
            ?? raw.image?.medium
            ?? raw.image?.small
        return RemoteArtist(
            id: String(raw.id),
            name: raw.name,
            url: URL(string: "https://play.qobuz.com/artist/\(raw.id)"),
            pictureURL: pic.flatMap(URL.init(string:))
        )
    }

    private nonisolated func mapAlbumRef(_ raw: QobuzAlbumRaw) -> RemoteAlbumRef {
        let title = raw.version.map { "\(raw.title) (\($0))" } ?? raw.title
        return RemoteAlbumRef(
            id: raw.id,
            title: title,
            url: raw.url.flatMap(URL.init(string:)) ?? URL(string: "https://play.qobuz.com/album/\(raw.id)"),
            coverArt: covers(raw.image),
            releaseYear: raw.released_at.map { Int(Date(timeIntervalSince1970: $0).year) },
            trackCount: raw.tracks_count
        )
    }

    private nonisolated func mapAlbum(_ raw: QobuzAlbumRaw, includeTracks: Bool) -> RemoteAlbum {
        let title = raw.version.map { "\(raw.title) (\($0))" } ?? raw.title
        let artists: [RemoteArtist] = (raw.artists?.map { mapArtist($0) }
            ?? raw.artist.map { [mapArtist($0)] }
            ?? [])
        let albumRef = mapAlbumRef(raw)
        let tracks = includeTracks
            ? (raw.tracks?.items ?? []).map { mapTrack($0, album: albumRef, fallbackArtists: artists) }
            : []
        return RemoteAlbum(
            id: raw.id,
            title: title,
            artists: artists,
            releaseYear: raw.released_at.map { Int(Date(timeIntervalSince1970: $0).year) },
            coverArt: covers(raw.image),
            url: raw.url.flatMap(URL.init(string:)) ?? URL(string: "https://play.qobuz.com/album/\(raw.id)"),
            trackCount: raw.tracks_count,
            tracks: tracks,
            serviceID: serviceID
        )
    }

    private nonisolated func mapTrack(
        _ raw: QobuzTrackRaw,
        album overrideAlbum: RemoteAlbumRef? = nil,
        fallbackArtists: [RemoteArtist] = []
    ) -> RemoteTrack {
        let title = raw.version.map { "\(raw.title) (\($0))" } ?? raw.title
        var artists: [RemoteArtist] = []
        if let p = raw.performer { artists.append(mapArtist(p)) }
        else if let a = raw.album?.artist { artists.append(mapArtist(a)) }
        if artists.isEmpty { artists = fallbackArtists }

        let albumRef = overrideAlbum ?? raw.album.map(mapAlbumRef)
        return RemoteTrack(
            id: String(raw.id),
            title: title,
            artists: artists,
            album: albumRef,
            trackNumber: raw.track_number,
            discNumber: raw.media_number,
            durationSeconds: raw.duration.map(Double.init),
            coverArt: albumRef?.coverArt ?? [],
            url: URL(string: "https://play.qobuz.com/track/\(raw.id)"),
            serviceID: serviceID,
            isLossless: true   // Qobuz at format_id=27 is FLAC; we ask for it on every track.
        )
    }

    private nonisolated func mapPlaylist(_ raw: QobuzPlaylistRaw) -> RemotePlaylist {
        let coverURL = raw.images?.first.flatMap(URL.init(string:))
        let cover = coverURL.map { [RemoteCoverArt(url: $0, width: nil, height: nil)] } ?? []
        let tracks = (raw.tracks?.items ?? []).map { mapTrack($0) }
        return RemotePlaylist(
            id: String(raw.id),
            title: raw.name,
            creator: raw.owner?.name,
            coverArt: cover,
            url: URL(string: "https://open.qobuz.com/playlist/\(raw.id)"),
            tracks: tracks,
            serviceID: serviceID
        )
    }

    private nonisolated func covers(_ image: QobuzImage) -> [RemoteCoverArt] {
        var arts: [RemoteCoverArt] = []
        if let s = image.thumbnail, let u = URL(string: s) {
            arts.append(RemoteCoverArt(url: u, width: 50, height: 50))
        }
        if let s = image.small, let u = URL(string: s) {
            arts.append(RemoteCoverArt(url: u, width: 230, height: 230))
        }
        if let s = image.large, let u = URL(string: s) {
            arts.append(RemoteCoverArt(url: u, width: 600, height: 600))
        }
        return arts
    }

    // MARK: - File extension inference

    private static func extensionFor(mime: String, formatID: Int?) -> String {
        // Qobuz mime types are usually "audio/flac" or "audio/mpeg"; the
        // format_id is authoritative when present (5=MP3 320, 6/7/27=FLAC).
        if let id = formatID {
            return id == 5 ? "mp3" : "flac"
        }
        let lower = mime.lowercased()
        if lower.contains("flac") { return "flac" }
        if lower.contains("mpeg") || lower.contains("mp3") { return "mp3" }
        return "flac" // safe default for an app that is FLAC-first
    }
}

// Tiny helper so we can extract the year from a `released_at` epoch without
// pulling in DateFormatter overhead. Calendar is thread-safe for read-only ops
// on Darwin so a single shared instance is fine.
private extension Date {
    var year: Int {
        let cal = Calendar(identifier: .gregorian)
        return cal.component(.year, from: self)
    }
}
