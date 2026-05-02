import Foundation
import WebKit

/// `StreamerProvider` backed by the lucida.to web service.
///
/// Goals:
///  - Zero user input — no accounts, no tokens, no settings UI.
///  - Anything lucida.to supports (Spotify / Tidal / Qobuz / Apple Music /
///    Deezer / SoundCloud / YouTube Music / Amazon Music / etc.) lands in
///    the library tagged.
///
/// All HTTP work happens inside a hidden `WKWebView` that has cleared
/// Cloudflare's bot challenge — see `LucidaWebController`.
@MainActor
final class LucidaWebProvider: NSObject, StreamerProvider {

    // MARK: - StreamerProvider conformance

    let serviceID = "lucida"
    let displayName = "Lucida"
    /// Hosts the lucida.to frontend accepts as paste targets. Listed
    /// individually because `StreamerRegistry.provider(for:)` does exact-host
    /// matching with `www.` stripping — no suffix wildcards.
    let hostnames: [String] = [
        "open.spotify.com", "spotify.com",
        "tidal.com", "listen.tidal.com",
        "qobuz.com", "play.qobuz.com", "open.qobuz.com",
        "deezer.com",
        "soundcloud.com",
        "music.apple.com",
        "music.amazon.com", "music.amazon.co.uk",
        "music.youtube.com",
        "lucida.to",
    ]
    var isConfigured: Bool { true }

    func login() async throws {
        try await controller.awaitReady()
    }

    func accountInfo() async throws -> StreamerAccount {
        try await controller.awaitReady()
        return StreamerAccount(
            displayName: "Anonymous via lucida.to",
            country: nil, lossless: true, hiRes: true
        )
    }

    /// Lucida's frontend has no free-text search endpoint; it's paste-URL
    /// only. We surface this honestly rather than fake catalog results.
    func search(_ query: String, limit: Int) async throws -> StreamerSearchResults {
        StreamerSearchResults(query: query, albums: [], tracks: [], artists: [])
    }

    func resolve(_ url: URL) async throws -> RemoteResolveResponse {
        try await controller.awaitReady()
        let raw = try await controller.callBridge(
            "window.__flac.metadata(\(jsString(url.absoluteString)))",
            as: LucidaMetadata.self
        )
        return raw.toRemote(originalURL: url)
    }

    func getStream(for track: RemoteTrack) async throws -> DownloadStream {
        try await controller.awaitReady()

        guard let serviceURL = track.url?.absoluteString else {
            throw StreamerError.unsupportedURL(URL(string: "lucida://missing")!)
        }

        // Use the per-track options the UI stashed before enqueueing, or
        // fall back to defaults (Original / metadata / no compat).
        let opts = optionsByTrackID[track.id] ?? .default
        let body = LucidaStreamRequest(url: serviceURL, options: opts)
        let bodyJSON = String(data: try JSONEncoder().encode(body), encoding: .utf8)!

        let initiate = try await controller.callBridge(
            "window.__flac.streamV2(\(bodyJSON), null)",
            as: LucidaStreamInitiateResponse.self
        )

        try await waitForCompletion(handoff: initiate.handoff, server: initiate.name)

        // Build the same redirect=true URL the website hands to window.open;
        // WKDownload follows the 302 internally and writes to disk.
        let inner = "/api/fetch/request/\(initiate.handoff)/download"
        let outer = "https://lucida.to/api/load?url=\(percent(inner))"
            + "&force=\(percent(initiate.name))&redirect=true"
        guard let dlURL = URL(string: outer) else {
            throw StreamerError.unavailable("could not build download URL")
        }

        // Set up the writer FIRST and bytes stream eagerly, then start the
        // download. Awaiting `awaitResponse()` blocks until headers arrive,
        // so the DownloadStream we hand back to the coordinator carries the
        // *real* extension and MIME — not a hardcoded "flac" guess that
        // breaks tagging when the source is MP3/AAC.
        let writer = LucidaDownloadWriter()
        let request = URLRequest(url: dlURL)
        let download = await controller.startDownload(request)
        download.delegate = writer
        let info = try await writer.awaitResponse()
        // Drop the per-track option entry now that the download is in flight.
        optionsByTrackID.removeValue(forKey: track.id)
        return writer.downloadStream(using: info)
    }

    // MARK: - Per-track options

    /// Options keyed by `RemoteTrack.id`. The UI calls `setOptions(_:for:)`
    /// just before `DownloadCoordinator.enqueue(_:)`; `getStream` reads and
    /// then removes the entry.
    private var optionsByTrackID: [String: LucidaOptions] = [:]

    func setOptions(_ options: LucidaOptions, for track: RemoteTrack) {
        optionsByTrackID[track.id] = options
    }

    // MARK: - Internals

    private let controller: LucidaWebController

    init(controller: LucidaWebController) {
        self.controller = controller
        super.init()
    }

    /// Repeatedly call `__flac.pollRequest(handoff, server)` until the job
    /// is `completed` or `error`. Lucida's status payload uses a freeform
    /// `message` for in-progress; we just echo the latest one back to the
    /// coordinator via `JobStatus.downloading` (no granular bytes yet).
    private func waitForCompletion(handoff: String, server: String) async throws {
        let deadline = Date().addingTimeInterval(180) // 3 minutes
        while Date() < deadline {
            let res = try await controller.callBridge(
                "window.__flac.pollRequest(\(jsString(handoff)), \(jsString(server)))",
                as: LucidaPollResponse.self
            )
            if res.status == "completed" { return }
            if res.status == "error" {
                throw StreamerError.unavailable(res.message ?? "lucida job failed")
            }
            try await Task.sleep(nanoseconds: 750_000_000)
        }
        throw StreamerError.unavailable("lucida job timed out")
    }

    private func jsString(_ s: String) -> String {
        // JSON encoding of a single string yields a properly quoted JS literal.
        let data = try! JSONEncoder().encode(s)
        return String(data: data, encoding: .utf8)!
    }

    private func percent(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}

// MARK: - Wire types

/// Loose decoder for the metadata payload. lucida.to returns a track or
/// album shape inspired by Lucida's `GetByUrlResponse`; field availability
/// varies by upstream service so almost everything is optional.
private struct LucidaMetadata: Decodable {
    let success: Bool?
    let type: String?
    let title: String?
    let artists: [Artist]?
    let album: Album?
    let durationMs: Double?
    let trackNumber: Int?
    let discNumber: Int?
    let isrc: String?
    let url: String?
    let coverArtwork: [Artwork]?
    let tracks: [TrackEntry]?

    struct Artist: Decodable { let name: String?; let url: String?; let pictures: [Artwork]? }
    struct Album: Decodable {
        let title: String?
        let releaseYear: Int?
        let trackCount: Int?
        let url: String?
        let coverArtwork: [Artwork]?
    }

    /// Lucida returns artwork two ways depending on the upstream service:
    /// either as `{url, width?, height?}` objects (Qobuz, Tidal) or as bare
    /// URL strings (Amazon Music, some Spotify variants). We accept both.
    struct Artwork: Decodable {
        let url: String?
        let width: Int?
        let height: Int?

        init(from decoder: Decoder) throws {
            if let s = try? decoder.singleValueContainer().decode(String.self) {
                self.url = s; self.width = nil; self.height = nil
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.url    = try c.decodeIfPresent(String.self, forKey: .url)
            self.width  = try c.decodeIfPresent(Int.self,    forKey: .width)
            self.height = try c.decodeIfPresent(Int.self,    forKey: .height)
        }

        private enum CodingKeys: String, CodingKey { case url, width, height }
    }
    struct TrackEntry: Decodable {
        let title: String?
        let artists: [Artist]?
        let durationMs: Double?
        let trackNumber: Int?
        let discNumber: Int?
        let isrc: String?
        let url: String?
    }

    func toRemote(originalURL: URL) -> RemoteResolveResponse {
        switch type {
        case "album":
            return .album(buildAlbum(originalURL: originalURL))
        default:
            return .track(buildTrack(originalURL: originalURL))
        }
    }

    private func buildTrack(originalURL: URL) -> RemoteTrack {
        let arts = (artists ?? []).map { a in
            RemoteArtist(
                id: a.name ?? "",
                name: a.name ?? "Unknown Artist",
                url: a.url.flatMap(URL.init(string:)),
                pictureURL: a.pictures?.first?.url.flatMap(URL.init(string:))
            )
        }
        let albumRef = album.map { al in
            RemoteAlbumRef(
                id: al.title ?? "",
                title: al.title ?? "",
                url: al.url.flatMap(URL.init(string:)),
                coverArt: (al.coverArtwork ?? []).compactMap(Self.toCover),
                releaseYear: al.releaseYear,
                trackCount: al.trackCount
            )
        }
        return RemoteTrack(
            id: originalURL.absoluteString,
            title: title ?? originalURL.lastPathComponent,
            artists: arts,
            album: albumRef,
            trackNumber: trackNumber,
            discNumber: discNumber,
            durationSeconds: durationMs.map { $0 / 1000 },
            coverArt: (coverArtwork ?? []).compactMap(Self.toCover),
            url: URL(string: url ?? originalURL.absoluteString) ?? originalURL,
            serviceID: "lucida",
            isLossless: true   // optimistic; lucida prefers lossless when available
        )
    }

    private func buildAlbum(originalURL: URL) -> RemoteAlbum {
        let albumArts = (album?.coverArtwork ?? coverArtwork ?? []).compactMap(Self.toCover)
        let mainArtists = (artists ?? []).map { a in
            RemoteArtist(id: a.name ?? "", name: a.name ?? "Unknown Artist",
                         url: nil, pictureURL: nil)
        }
        let trackList: [RemoteTrack] = (tracks ?? []).enumerated().map { idx, t in
            RemoteTrack(
                id: "\(originalURL.absoluteString)#\(idx)",
                title: t.title ?? "Track \(idx + 1)",
                artists: (t.artists ?? artists ?? []).map { a in
                    RemoteArtist(id: a.name ?? "", name: a.name ?? "Unknown Artist",
                                 url: nil, pictureURL: nil)
                },
                album: RemoteAlbumRef(
                    id: album?.title ?? "", title: album?.title ?? "",
                    url: originalURL, coverArt: albumArts,
                    releaseYear: album?.releaseYear, trackCount: album?.trackCount
                ),
                trackNumber: t.trackNumber ?? (idx + 1),
                discNumber: t.discNumber,
                durationSeconds: t.durationMs.map { $0 / 1000 },
                coverArt: albumArts,
                url: URL(string: t.url ?? originalURL.absoluteString) ?? originalURL,
                serviceID: "lucida",
                isLossless: true
            )
        }
        return RemoteAlbum(
            id: originalURL.absoluteString,
            title: album?.title ?? title ?? originalURL.lastPathComponent,
            artists: mainArtists,
            releaseYear: album?.releaseYear,
            coverArt: albumArts,
            url: originalURL,
            trackCount: album?.trackCount ?? trackList.count,
            tracks: trackList,
            serviceID: "lucida"
        )
    }

    private static func toCover(_ a: Artwork) -> RemoteCoverArt? {
        guard let s = a.url, let u = URL(string: s) else { return nil }
        return RemoteCoverArt(url: u, width: a.width, height: a.height)
    }
}

private struct LucidaStreamRequest: Encodable {
    let url: String
    let metadata: Bool
    let compat: Bool
    let `private`: Bool
    let handoff: Bool
    let account: Account
    let upload: Upload
    let downscale: String

    struct Account: Encodable { let id: String; let type: String }
    struct Upload: Encodable { let enabled: Bool; let service: String }

    init(url: String, options: LucidaOptions) {
        self.url        = url
        self.metadata   = options.addMetadata
        self.compat     = options.compatibility
        self.private    = true
        self.handoff    = true
        self.account    = .init(id: options.region, type: "country")
        self.upload     = .init(enabled: false, service: "pixeldrain")
        self.downscale  = options.format.rawValue
    }
}

private struct LucidaStreamInitiateResponse: Decodable {
    let success: Bool?
    let handoff: String
    /// Server name that owns this job; passed back as `force=` to keep
    /// every subsequent call routed to the same backend node.
    let name: String
    let skipbo: String?
    let skipboExpiration: Double?
}

private struct LucidaPollResponse: Decodable {
    let success: Bool?
    let status: String?
    let message: String?
}
