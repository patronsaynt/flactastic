import Foundation

/// File-backed secret store for streaming-service credentials.
///
/// Lives at `~/Library/Application Support/fm.flactastic.streaming/credentials.json`
/// with `0600` file permissions (owner read/write only). For a personal-use
/// Mac app, this is the standard pragmatic alternative to Keychain — Keychain
/// prompts on every read when the binary isn't signed with a stable identity,
/// which makes routine `swift build` cycles unusable. The file is readable
/// only by your user account; it is not encrypted at rest, so don't paste a
/// shared corporate Qobuz account here.
struct CredentialStore: Sendable {
    private let fileURL: URL

    init(serviceID: String = "fm.flactastic.streaming") {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let dir = appSupport.appendingPathComponent(serviceID, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("credentials.json")
    }

    enum Key: String, Sendable {
        case qobuzAppID            = "qobuz.appId"
        case qobuzAppSecret        = "qobuz.appSecret"
        case qobuzUsername         = "qobuz.username"
        case qobuzPassword         = "qobuz.password"
        case qobuzUserAuthToken    = "qobuz.userAuthToken"
        case deezerARL             = "deezer.arl"
        case soundCloudOAuthToken  = "soundcloud.oauth"
    }

    func read(_ key: Key) -> String? {
        loadAll()[key.rawValue]
    }

    func write(_ value: String?, for key: Key) {
        var all = loadAll()
        if let value, !value.isEmpty {
            all[key.rawValue] = value
        } else {
            all.removeValue(forKey: key.rawValue)
        }
        saveAll(all)
    }

    func delete(_ key: Key) { write(nil, for: key) }

    // MARK: - File I/O

    private func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private func saveAll(_ dict: [String: String]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        // Write atomically, then chmod 0600 so the file is readable only by
        // the current user. The macOS user-domain Application Support dir
        // already lives under ~/, but defense in depth costs nothing.
        do {
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            // Surface to console only — credential persistence failures are
            // recoverable (the user can re-enter on next launch).
            print("CredentialStore write failed: \(error)")
        }
    }
}
