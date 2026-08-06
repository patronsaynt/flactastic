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
        request.setValue("FLACtastic (https://github.com/patronsaynt/flactastic)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        await semaphore.wait()
        defer { Task { await semaphore.signal() } }

        let (data, response) = try await sendWithRetry(request)
        guard let http = response as? HTTPURLResponse else {
            throw LrcLibClientError.badResponse(-1)
        }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw LrcLibClientError.badResponse(http.statusCode)
        }
        return try JSONDecoder().decode(LrcLibResponse.self, from: data)
    }

    /// Transient transport failures that are worth a second attempt on a
    /// fresh connection. `secureConnectionFailed` (-1200) is the common one:
    /// a TLS handshake that lost the race, not a real trust problem — a
    /// genuine bad certificate surfaces as `serverCertificate*` instead and
    /// is deliberately absent here so we never retry past a trust failure.
    private static let retryableCodes: Set<URLError.Code> = [
        .secureConnectionFailed,
        .networkConnectionLost,
        .timedOut,
        .cannotConnectToHost,
    ]

    /// Issue the request, retrying transient transport errors with a short
    /// exponential backoff. Caps at `maxAttempts` so a genuinely unreachable
    /// host still fails fast rather than stalling the fetcher's semaphore.
    private func sendWithRetry(
        _ request: URLRequest,
        maxAttempts: Int = 3
    ) async throws -> (Data, URLResponse) {
        var attempt = 1
        while true {
            do {
                return try await session.data(for: request)
            } catch let error as URLError
                where Self.retryableCodes.contains(error.code) && attempt < maxAttempts {
                // 250ms, then 500ms. Jittered so a batch of tracks that all
                // failed together doesn't retry in lockstep.
                let backoff = 0.25 * pow(2.0, Double(attempt - 1))
                let jitter = Double.random(in: 0...0.1)
                try await Task.sleep(nanoseconds: UInt64((backoff + jitter) * 1_000_000_000))
                attempt += 1
            }
        }
    }
}
