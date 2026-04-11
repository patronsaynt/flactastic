import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Settings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
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

            // Music folder section
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
                    .buttonStyle(MonochromeButtonStyle())
                }
            }

            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 480, height: 300)
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
