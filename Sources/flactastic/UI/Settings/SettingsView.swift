import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Settings.self) private var settings
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
            Group {
                switch selectedTab {
                case .config:
                    ConfigSettingsSection(openFolder: openFolder)
                case .appearance:
                    AppearanceSettingsSection()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 520, height: 380)
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
        }
    }
}

// MARK: - Tab model

private enum SettingsTab: String, CaseIterable, Identifiable {
    case config = "Config"
    case appearance = "Appearance"
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

            Toggle("Menu Bar Mini-Player", isOn: $settings.showMenuBarPlayer)
                .toggleStyle(.switch)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textSecondary)
                .tint(Theme.accent)
        }
    }
}

// MARK: - Appearance tab

private struct AppearanceSettingsSection: View {
    @Environment(Settings.self) private var settings

    /// Slider range: 0.9 (small) to 1.35 (large). Default 1.0.
    private let scaleRange: ClosedRange<Double> = 0.9...1.35

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Toggle("Light Mode", isOn: $settings.useLightMode)
                .toggleStyle(.switch)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textSecondary)
                .tint(Theme.accent)

            Toggle("List Layout", isOn: $settings.useListLayout)
                .toggleStyle(.switch)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textSecondary)
                .tint(Theme.accent)

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
