import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Settings.self) private var settings
    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: SettingsTab = .config

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Header
            HStack {
                Text("Settings")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            // Tab bar
            SettingsTabBar(selectedTab: $selectedTab)

            // Tab content
            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    switch selectedTab {
                    case .config:
                        ConfigSettingsSection(openFolder: openFolder)
                    case .appearance:
                        AppearanceSettingsSection()
                    case .visualizer:
                        VisualizerSettingsSection()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.md)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 600, height: 560)
        .background(Theme.surface)
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose your music folder"
        if panel.runModal() == .OK, let url = panel.url {
            settings.lastRootPath = url.path
            library.openFolder(url)
            playlistStore.load(from: url)
        }
    }
}

// MARK: - Tab model

private enum SettingsTab: String, CaseIterable, Identifiable {
    case config = "Config"
    case appearance = "Appearance"
    case visualizer = "Visualizer"
    var id: String { rawValue }
}

// MARK: - Tab bar

private struct SettingsTabBar: View {
    @Binding var selectedTab: SettingsTab
    @Namespace private var tabAnimation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(3)
        .background(
            Capsule().fill(Theme.background)
        )
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            Text(tab.rawValue)
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textTertiary)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Theme.surfaceElevated)
                            .matchedGeometryEffect(id: "activeSettingsTab", in: tabAnimation)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Config tab

private struct ConfigSettingsSection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Settings.self) private var settings
    @Environment(SpotifyAuthController.self) private var spotifyAuth
    @Environment(\.debugMode) private var debugMode
    let openFolder: () -> Void

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Music Folder")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: Theme.Spacing.md) {
                    if let rootURL = library.rootURL {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Theme.textTertiary)
                        Text(rootURL.path)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("No folder selected")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer()

                    Button("Choose Folder…") {
                        openFolder()
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }

            Divider().foregroundStyle(Theme.divider)

            HStack {
                Text("Menu Bar Mini-Player")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Toggle("", isOn: $settings.showMenuBarPlayer)
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .labelsHidden()
            }

            HStack {
                Text("Auto-Fetch Artist Images")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Toggle("", isOn: $settings.autoFetchArtistImages)
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .labelsHidden()
            }

            HStack {
                Text("Discord Rich Presence")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Toggle("", isOn: $settings.discordRichPresenceEnabled)
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .labelsHidden()
            }

            Divider().foregroundStyle(Theme.divider)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Spotify account")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)
                Text("Connect your Spotify account to browse and download your own playlists, including private ones, in full.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Spacing.md) {
                    switch spotifyAuth.state {
                    case .disconnected:
                        Button("Connect Spotify") {
                            Task { await spotifyAuth.connect() }
                        }
                        .buttonStyle(PillButtonStyle(isPrimary: true))
                    case .connecting:
                        ProgressView().controlSize(.small)
                        Text("Connecting…")
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.textSecondary)
                    case .connected(let name):
                        HStack(spacing: 6) {
                            Circle().fill(Theme.qualityCD).frame(width: 7, height: 7)
                            Text("Connected as ")
                                .foregroundStyle(Theme.textSecondary)
                            + Text(name).foregroundStyle(Theme.textPrimary).fontWeight(.medium)
                        }
                        .font(Theme.Font.body)
                        Spacer()
                        Button("Disconnect") { spotifyAuth.disconnect() }
                            .buttonStyle(PillButtonStyle())
                    }
                }
            }

            Divider().foregroundStyle(Theme.divider)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Spotify API keys (legacy)")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)
                Text("Optional. Used only for the public-link paste fallback when you're not connected above. Without keys, pasted public playlists use Spotify's preview, capped at 100 tracks. Add a free Spotify Developer app's Client ID and Secret (developer.spotify.com → Dashboard → Create app) to fetch pasted public playlists of any length.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("Client ID")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 90, alignment: .leading)
                    TextField("Client ID", text: $settings.spotifyClientID)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Client Secret")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 90, alignment: .leading)
                    SecureField("Client Secret", text: $settings.spotifyClientSecret)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if debugMode {
                Divider().foregroundStyle(Theme.divider)

                Text("Downloads")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show VPN Advisory")
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.textSecondary)
                        Text("Show a reminder to use a VPN when opening the Downloads tab.")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.showVpnNotice)
                        .toggleStyle(.switch)
                        .tint(Theme.accent)
                        .labelsHidden()
                }
            }
        }
    }
}

// MARK: - Visualizer tab

private struct VisualizerSettingsSection: View {
    @Environment(Settings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Big Picture Fullscreen Toggle")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Show a small icon in Big Picture mode to enter or exit fullscreen.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $settings.showBigPictureFullScreenToggle)
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .labelsHidden()
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fetch Lyrics from lrclib.net")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Enables the Lyrics visualizer mode. Lookups are cached on disk; disable to stay fully offline.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $settings.lyricsLookupEnabled)
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .labelsHidden()
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save Lyrics to Audio Files")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Embed fetched lyrics into the LYRICS tag on each file (Vorbis, ID3v2 USLT, MP4). Other players will pick them up automatically.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $settings.saveLyricsToFiles)
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .labelsHidden()
                    .disabled(!settings.lyricsLookupEnabled)
            }
        }
    }
}

// MARK: - Appearance tab

private struct AppearanceSettingsSection: View {
    @Environment(Settings.self) private var settings

    private let scaleRange: ClosedRange<Double> = 0.9...1.35

    private func settingsToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .labelsHidden()
        }
    }

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            settingsToggle("Light Mode", isOn: $settings.useLightMode)
            settingsToggle("List Layout", isOn: $settings.useListLayout)
            settingsToggle("Group Albums by Artist (Icon View)", isOn: $settings.groupByArtist)
            settingsToggle("Rounded Album Art", isOn: $settings.roundedArtwork)
            settingsToggle("Artwork Drop Shadow", isOn: $settings.showArtworkShadow)
            settingsToggle("Fade Animations", isOn: $settings.fadeAnimationsEnabled)

            HStack {
                Text("Fade Direction")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Picker("", selection: $settings.fadeAnimationDirection) {
                    ForEach(FadeAnimationDirection.allCases) { dir in
                        Text(dir.label).tag(dir)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(!settings.fadeAnimationsEnabled)
            }

            Divider().foregroundStyle(Theme.divider)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("UI Scale")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.textSecondary)

                    Spacer()

                    Text("\(Int((settings.uiScale * 100).rounded()))%")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }

                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "textformat.size.smaller")
                        .foregroundStyle(Theme.textTertiary)

                    Slider(
                        value: $settings.uiScale,
                        in: scaleRange,
                        step: 0.05
                    )
                    .tint(Theme.accent)

                    Image(systemName: "textformat.size.larger")
                        .foregroundStyle(Theme.textTertiary)

                    Button {
                        settings.uiScale = 1.0
                    } label: {
                        Text("Reset")
                            .font(Theme.Font.caption)
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(abs(settings.uiScale - 1.0) < 0.001)
                }

                Text("Scales text and controls throughout the app.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}
