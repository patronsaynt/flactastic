import SwiftUI

/// Streaming-services pane in the Settings sheet. Reads/writes credentials via
/// `CredentialStore` (Keychain) — never UserDefaults — and lets the user run a
/// "Test login" probe per provider.
struct StreamingSettingsView: View {
    @Environment(StreamerRegistry.self) private var registry

    @State private var qobuzAppID: String = ""
    @State private var qobuzAppSecret: String = ""
    @State private var qobuzUsername: String = ""
    @State private var qobuzPassword: String = ""
    @State private var deezerARL: String = ""
    @State private var soundCloudOAuth: String = ""

    @State private var qobuzStatus: String?
    @State private var deezerStatus: String?
    @State private var soundCloudStatus: String?

    private let credentials = CredentialStore()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Streaming Services")
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)

            providerSection(
                title: "Qobuz",
                description: "Native FLAC up to hi-res. Requires an app_id / app_secret pair (extracted from the Qobuz web player) plus your account login.",
                fields: {
                    Group {
                        labeledField("App ID", text: $qobuzAppID, secure: false)
                        labeledField("App Secret", text: $qobuzAppSecret, secure: true)
                        labeledField("Username / Email", text: $qobuzUsername, secure: false)
                        labeledField("Password", text: $qobuzPassword, secure: true)
                    }
                },
                onSave: saveQobuz,
                onTest: testQobuz,
                status: qobuzStatus
            )

            Divider().foregroundStyle(Theme.divider)

            providerSection(
                title: "Deezer",
                description: "Native FLAC for HiFi subscribers. Provide your ARL cookie from deezer.com (visible in browser dev tools under Application → Cookies).",
                fields: {
                    labeledField("ARL Cookie", text: $deezerARL, secure: true)
                },
                onSave: saveDeezer,
                onTest: testDeezer,
                status: deezerStatus
            )

            Divider().foregroundStyle(Theme.divider)

            providerSection(
                title: "SoundCloud",
                description: "Lossy only. Provider not yet implemented — SoundCloud's client-key discovery requires HTML scraping that is brittle to maintain. Credentials are stored here in advance so a future update can enable it without re-entering anything.",
                fields: {
                    labeledField("OAuth Token", text: $soundCloudOAuth, secure: true)
                },
                onSave: saveSoundCloud,
                onTest: nil,
                status: soundCloudStatus
            )
        }
        .onAppear(perform: loadFromKeychain)
    }

    // MARK: - Helpers

    private func labeledField(_ label: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private func providerSection<Fields: View>(
        title: String,
        description: String,
        @ViewBuilder fields: () -> Fields,
        onSave: @escaping () -> Void,
        onTest: (() -> Void)?,
        status: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
            Text(description)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)

            fields()

            HStack {
                Button("Save") { onSave() }
                    .buttonStyle(PillButtonStyle())
                if let onTest {
                    Button("Test login") { onTest() }
                        .buttonStyle(PillButtonStyle())
                }
                Spacer()
                if let status {
                    Text(status)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Persistence + actions

    private func loadFromKeychain() {
        qobuzAppID = credentials.read(.qobuzAppID) ?? ""
        qobuzAppSecret = credentials.read(.qobuzAppSecret) ?? ""
        qobuzUsername = credentials.read(.qobuzUsername) ?? ""
        qobuzPassword = credentials.read(.qobuzPassword) ?? ""
        deezerARL = credentials.read(.deezerARL) ?? ""
        soundCloudOAuth = credentials.read(.soundCloudOAuthToken) ?? ""
    }

    private func saveQobuz() {
        credentials.write(qobuzAppID, for: .qobuzAppID)
        credentials.write(qobuzAppSecret, for: .qobuzAppSecret)
        credentials.write(qobuzUsername, for: .qobuzUsername)
        credentials.write(qobuzPassword, for: .qobuzPassword)
        credentials.delete(.qobuzUserAuthToken) // force re-login on next call
        // Refresh the registry so the provider sees the new creds.
        let provider = QobuzProvider(credentials: credentials)
        registry.register(provider)
        qobuzStatus = "Saved."
    }

    private func saveDeezer() {
        let cleaned = deezerARL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .removingPercentEncoding ?? deezerARL.trimmingCharacters(in: .whitespacesAndNewlines)
        deezerARL = cleaned
        credentials.write(cleaned, for: .deezerARL)
        let provider = DeezerProvider(credentials: credentials)
        registry.register(provider)
        if cleaned.count < 100 {
            deezerStatus = "Saved, but ARL looks too short (\(cleaned.count) chars). Expected ~192 hex chars."
        } else if cleaned.contains(where: { !$0.isHexDigit }) {
            deezerStatus = "Saved, but value contains non-hex characters — probably the wrong cookie."
        } else {
            deezerStatus = "Saved."
        }
    }

    private func testDeezer() {
        deezerStatus = "Testing…"
        Task {
            do {
                guard let provider = registry.provider(serviceID: "deezer") else {
                    deezerStatus = "Provider not registered. Save credentials first."
                    return
                }
                let info = try await provider.accountInfo()
                let qual = info.lossless ? "Lossless" : "Lossy"
                deezerStatus = "OK — \(info.country ?? "?") (\(qual))"
            } catch {
                deezerStatus = "Failed: \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
            }
        }
    }

    private func saveSoundCloud() {
        credentials.write(soundCloudOAuth, for: .soundCloudOAuthToken)
        soundCloudStatus = "Saved (provider pending)."
    }

    private func testQobuz() {
        qobuzStatus = "Testing…"
        Task {
            do {
                guard let provider = registry.provider(serviceID: "qobuz") else {
                    qobuzStatus = "Provider not registered. Save credentials first."
                    return
                }
                let info = try await provider.accountInfo()
                let qual = info.hiRes ? "Hi-Res" : info.lossless ? "Lossless" : "Lossy"
                qobuzStatus = "OK — \(info.displayName ?? "logged in") (\(qual))"
            } catch {
                qobuzStatus = "Failed: \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
            }
        }
    }
}
