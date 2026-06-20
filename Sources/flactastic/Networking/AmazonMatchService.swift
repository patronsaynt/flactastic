import Foundation

/// Maps a streaming-service track URL (typically Spotify) to its Amazon Music
/// equivalent using the public Odesli / song.link API. No API key required.
///
/// Endpoint: GET https://api.song.link/v1-alpha.1/links?url=<track url>
/// We read `linksByPlatform.amazonMusic.url` from the response.
///
/// Why Amazon: when fed back into Lucida, Amazon Music links resolve to higher-
/// quality streams more reliably than the original Spotify link. This realises
/// the "isrc/songlink upgrade" anticipated in LucidaWebController.
///
/// Best-effort by design: any failure (no match, rate-limit, timeout, transport
/// error) returns `nil` so the caller can fall back to the original URL and let
/// Lucida's own detector handle it.
actor AmazonMatchService {
    private let session: URLSession

    /// Odesli's unauthenticated quota is ~10 requests/minute. Enforce a minimum
    /// gap between calls so a run of cache-miss / failed tracks doesn't burst.
    private let minimumInterval: TimeInterval = 6.5
    private var lastRequestAt: Date?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 20
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    /// Returns the Amazon Music URL for the given track URL, or `nil` when no
    /// match exists or the lookup fails for any reason.
    func amazonURL(forTrack url: URL) async -> URL? {
        await throttle()

        var components = URLComponents(string: "https://api.song.link/v1-alpha.1/links")
        components?.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "songIfSingle", value: "true"),
        ]
        guard let endpoint = components?.url else { return nil }

        var request = URLRequest(url: endpoint)
        request.setValue("FLACtastic", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            // Single retry on rate-limit, then give up (caller falls back).
            if http.statusCode == 429 {
                let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init)) ?? 10
                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                return await amazonURLOnce(endpoint: endpoint, request: request)
            }
            guard (200..<300).contains(http.statusCode) else { return nil }

            return Self.decodeAmazonURL(from: data)
        } catch {
            return nil
        }
    }

    /// Single attempt without the throttle/retry wrapper, used after a 429 wait.
    private func amazonURLOnce(endpoint: URL, request: URLRequest) async -> URL? {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            return Self.decodeAmazonURL(from: data)
        } catch {
            return nil
        }
    }

    /// Sleep until at least `minimumInterval` has elapsed since the last request.
    private func throttle() async {
        if let last = lastRequestAt {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < minimumInterval {
                let wait = minimumInterval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        lastRequestAt = Date()
    }

    private static func decodeAmazonURL(from data: Data) -> URL? {
        guard let payload = try? JSONDecoder().decode(OdesliResponse.self, from: data),
              let urlString = payload.linksByPlatform?.amazonMusic?.url else {
            return nil
        }
        return URL(string: urlString)
    }
}

// MARK: - Wire types

/// Loose decoder for the song.link response — we only need the Amazon Music URL.
private struct OdesliResponse: Decodable {
    let linksByPlatform: LinksByPlatform?

    struct LinksByPlatform: Decodable {
        let amazonMusic: PlatformLink?
    }
    struct PlatformLink: Decodable {
        let url: String?
    }
}
