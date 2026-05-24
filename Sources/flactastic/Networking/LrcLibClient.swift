import Foundation

/// Minimal lrclib.net client. Free, no API key — lrclib is the de-facto
/// public lyrics database used by Plexamp, Lollypop, Strawberry, etc.
/// Endpoint: GET https://lrclib.net/api/get?artist_name=...&track_name=...
struct LrcLibResponse: Decodable, Sendable {
    let id: Int?
    let plainLyrics: String?
    let syncedLyrics: String?
    let instrumental: Bool?
}

enum LrcLibClientError: Error {
    case invalidQuery
    case badResponse(Int)
}

actor LrcLibClient {
    static let shared = LrcLibClient()

    private let session: URLSession
    /// Polite concurrency cap so we don't burst lrclib on rapid track skips.
    private let semaphore = AsyncSemaphore(limit: 4)

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    /// Fetch lyrics for a track. Returns `nil` on a 404 (no match);
    /// throws `badResponse` for any other non-2xx status.
    func fetchLyrics(
        artist: String,
        title: String,
        album: String?,
        duration: TimeInterval?
    ) async throws -> LrcLibResponse? {
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArtist.isEmpty, !trimmedTitle.isEmpty else {
            throw LrcLibClientError.invalidQuery
        }

        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "artist_name", value: trimmedArtist),
            URLQueryItem(name: "track_name", value: trimmedTitle),
        ]
        if let album, !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw LrcLibClientError.invalidQuery }

        var request = URLRequest(url: url)
        // lrclib's docs request a User-Agent that identifies the client.
        request.setValue("FLACtastic (https://github.com/anthropics)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        await semaphore.wait()
        defer { Task { await semaphore.signal() } }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LrcLibClientError.badResponse(-1)
        }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw LrcLibClientError.badResponse(http.statusCode)
        }
        return try JSONDecoder().decode(LrcLibResponse.self, from: data)
    }
}
