import Foundation
import CryptoKit

/// Low-level signed-request helper for the Qobuz `api.json/0.2/...` API.
/// Mirrors the signing logic from
/// `Resources/lucida/src/streamers/qobuz/main.ts:117-141`.
///
/// Signature algorithm:
///   toHash = path.replace("/", "")
///         + ∑(sorted(key) for key in params if key not in {"app_id", "user_auth_token"}) + value
///         + timestamp
///         + appSecret
///   signed_params = params + { request_ts: timestamp, request_sig: md5(toHash) }
struct QobuzAPI: Sendable {
    let appID: String
    let appSecret: String
    var userAuthToken: String?

    private let session: URLSession

    init(appID: String, appSecret: String, userAuthToken: String? = nil, session: URLSession = .shared) {
        self.appID = appID
        self.appSecret = appSecret
        self.userAuthToken = userAuthToken
        self.session = session
    }

    private static let host = "https://www.qobuz.com/api.json/0.2/"

    private static let defaultHeaders: [String: String] = [
        "X-Device-Platform": "android",
        "X-Device-Model": "Pixel 3",
        "X-Device-Os-Version": "10",
        "X-Device-Manufacturer-Id": "ffffffff-5783-1f51-ffff-ffffef05ac4a",
        "X-App-Version": "5.16.1.5",
        "User-Agent": "Dalvik/2.1.0 (Linux; U; Android 10; Pixel 3 Build/QP1A.190711.020)) QobuzMobileAndroid/5.16.1.5-b21041415"
    ]

    // MARK: - Public

    /// Unsigned GET — used for catalog browsing endpoints (`catalog/search`,
    /// `track/get`, `album/get`, `artist/get`, `playlist/get`).
    func get<T: Decodable>(_ path: String, params: [String: String]) async throws -> T {
        let url = try Self.buildURL(path: path, params: params)
        return try await perform(url: url)
    }

    /// Signed GET — required for `track/getFileUrl` and `user/login`.
    func getSigned<T: Decodable>(_ path: String, params: [String: String]) async throws -> T {
        var signed = params
        let signature = signature(path: path, params: params)
        signed["request_ts"] = String(signature.timestamp)
        signed["request_sig"] = signature.hash
        let url = try Self.buildURL(path: path, params: signed)
        return try await perform(url: url)
    }

    // MARK: - Signing

    struct Signature: Sendable {
        let timestamp: Int
        let hash: String
    }

    /// Computes the MD5 signature for a Qobuz API call. Made `internal` so
    /// the test target can verify against a known fixture.
    func signature(path: String, params: [String: String], now: Date = Date()) -> Signature {
        let timestamp = Int(now.timeIntervalSince1970)
        var toHash = path.replacingOccurrences(of: "/", with: "")
        for key in params.keys.sorted() {
            if key == "app_id" || key == "user_auth_token" { continue }
            toHash += key + params[key, default: ""]
        }
        toHash += String(timestamp) + appSecret
        let digest = Insecure.MD5.hash(data: Data(toHash.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return Signature(timestamp: timestamp, hash: hex)
    }

    // MARK: - Internals

    private static func buildURL(path: String, params: [String: String]) throws -> URL {
        guard var components = URLComponents(string: host + path) else {
            throw StreamerError.unsupportedURL(URL(string: host + path) ?? URL(fileURLWithPath: "/"))
        }
        components.queryItems = params
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            throw StreamerError.decoding("could not build Qobuz URL for path \(path)")
        }
        return url
    }

    private func perform<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in Self.defaultHeaders { request.setValue(v, forHTTPHeaderField: k) }
        if let token = userAuthToken {
            request.setValue(token, forHTTPHeaderField: "X-User-Auth-Token")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StreamerError.http(status: -1, body: "no response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw StreamerError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw StreamerError.decoding(String(describing: error))
        }
    }
}
