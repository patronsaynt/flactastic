import Foundation

/// Thin wrapper over Deezer's `gw-light.php` JSON-RPC. Uses a *dedicated*
/// URLSession with its own HTTPCookieStorage so the user's `arl=` cookie
/// doesn't bleed into the shared session.
///
/// Mirrors the request shape from
/// `Resources/lucida/src/streamers/deezer/main.ts:109-174`.
actor DeezerAPI {
    private let arl: String
    private(set) var apiToken: String?
    private(set) var licenseToken: String?
    private(set) var country: String?
    private(set) var availableFormats: Set<DeezerFormat> = [.MP3_128]

    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage

    init(arl: String) {
        // Strip whitespace/newlines silently introduced when pasting from
        // browser devtools, and percent-decode in case the value got copied
        // URL-encoded. A clean ARL is plain hex.
        let trimmed = arl.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        self.arl = decoded

        let config = URLSessionConfiguration.ephemeral
        let cookies = HTTPCookieStorage()
        config.httpCookieStorage = cookies
        config.httpCookieAcceptPolicy = .always
        self.session = URLSession(configuration: config)
        self.cookieStorage = cookies

        // Seed the ARL cookie so the very first gw-light request is authenticated.
        if let cookie = HTTPCookie(properties: [
            .domain: ".deezer.com",
            .path: "/",
            .name: "arl",
            .value: decoded,
            .secure: "TRUE"
        ]) {
            cookies.setCookie(cookie)
        }
    }

    private static let gwURL = "https://www.deezer.com/ajax/gw-light.php"

    private static let baseHeaders: [String: String] = [
        "Accept": "*/*",
        "Content-Type": "text/plain;charset=UTF-8",
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36",
        "Origin": "https://www.deezer.com",
        "Referer": "https://www.deezer.com/",
        "Accept-Language": "en-US,en;q=0.9"
    ]

    /// Bootstrap the session: calls `deezer.getUserData` so the server hands us
    /// a `sid` cookie + `checkForm` (api token). Throws on invalid ARL.
    func login() async throws {
        let userData: DeezerUserData = try await call(
            method: "deezer.getUserData",
            params: [:],
            useApiToken: false
        )
        if userData.USER.USER_ID == 0 {
            throw StreamerError.authenticationFailed(service: "Deezer", reason: "ARL is invalid or expired")
        }
        apiToken = userData.checkForm
        licenseToken = userData.USER.OPTIONS?.license_token
        country = userData.COUNTRY
        availableFormats = [.MP3_128]
        if userData.USER.OPTIONS?.web_hq == true { availableFormats.insert(.MP3_320) }
        if userData.USER.OPTIONS?.web_lossless == true { availableFormats.insert(.FLAC) }
    }

    /// Generic gw-light POST. Decodes `results` (the inner payload). Performs
    /// one session-renewal retry when the server returns
    /// `VALID_TOKEN_REQUIRED` / `NEED_USER_AUTH_REQUIRED`.
    func call<T: Decodable & Sendable>(
        method: String,
        params: [String: any Sendable],
        useApiToken: Bool = true
    ) async throws -> T {
        try await call(method: method, params: params, useApiToken: useApiToken, attempt: 0)
    }

    private func call<T: Decodable & Sendable>(
        method: String,
        params: [String: any Sendable],
        useApiToken: Bool,
        attempt: Int
    ) async throws -> T {
        let token = useApiToken ? (apiToken ?? "") : ""
        var components = URLComponents(string: Self.gwURL)!
        components.queryItems = [
            URLQueryItem(name: "method", value: method),
            URLQueryItem(name: "input", value: "3"),
            URLQueryItem(name: "api_version", value: "1.0"),
            URLQueryItem(name: "api_token", value: token),
            URLQueryItem(name: "cid", value: String(Int.random(in: 0..<1_000_000_000)))
        ]
        guard let url = components.url else {
            throw StreamerError.decoding("could not build Deezer gw-light URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (k, v) in Self.baseHeaders { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StreamerError.http(status: -1, body: "no response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw StreamerError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }

        // Body shape: { "error": [] | { "TYPE": "msg" }, "results": <T> }
        // Decoding error first because { results } is generic.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StreamerError.decoding("Deezer body is not a JSON object")
        }
        if let errorObj = json["error"] as? [String: Any], let key = errorObj.keys.first {
            let msg = errorObj[key] as? String ?? ""
            if attempt == 0 && (key == "VALID_TOKEN_REQUIRED" || key == "NEED_USER_AUTH_REQUIRED") {
                try await login()
                return try await call(method: method, params: params, useApiToken: useApiToken, attempt: 1)
            }
            throw StreamerError.authenticationFailed(service: "Deezer", reason: "\(key): \(msg)")
        }
        guard let resultsAny = json["results"] else {
            throw StreamerError.decoding("Deezer response missing `results`")
        }
        let resultsData = try JSONSerialization.data(withJSONObject: resultsAny)
        return try JSONDecoder().decode(T.self, from: resultsData)
    }

    // MARK: - Stream URL

    /// Fetches the CDN URL for a given track at the requested format. Mirrors
    /// `Resources/lucida/src/streamers/deezer/main.ts:472-504`.
    func getStreamURL(trackToken: String, format: DeezerFormat) async throws -> URL {
        var request = URLRequest(url: URL(string: "https://media.deezer.com/v1/get_url")!)
        request.httpMethod = "POST"
        for (k, v) in Self.baseHeaders { request.setValue(v, forHTTPHeaderField: k) }

        let body: [String: Any] = [
            "license_token": licenseToken ?? "",
            "media": [[
                "type": "FULL",
                "formats": [["cipher": "BF_CBC_STRIPE", "format": format.rawValue]]
            ]],
            "track_tokens": [trackToken]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw StreamerError.http(
                status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                body: String(data: data, encoding: .utf8)
            )
        }
        let parsed = try JSONDecoder().decode(DeezerMediaResponse.self, from: data)
        guard let urlStr = parsed.data?.first?.media?.first?.sources?.first?.url,
              let url = URL(string: urlStr) else {
            throw StreamerError.unavailable("Deezer did not return a CDN URL — track may be unavailable in your region.")
        }
        return url
    }

    /// Refresh an expired track token via `song.getData`.
    func refreshTrackToken(trackID: String) async throws -> String {
        let track: DeezerTrackRaw = try await call(
            method: "song.getData",
            params: ["sng_id": trackID, "array_default": ["TRACK_TOKEN"]]
        )
        guard let token = track.TRACK_TOKEN else {
            throw StreamerError.unavailable("Deezer did not return a fresh track token.")
        }
        return token
    }

    /// Direct streaming download from the CDN URL — no auth, just a GET.
    func downloadCDN(url: URL) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in Self.baseHeaders { request.setValue(v, forHTTPHeaderField: k) }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw StreamerError.http(
                status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                body: nil
            )
        }
        return (bytes, http)
    }
}
