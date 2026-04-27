import SwiftUI
import AppKit

struct OnboardingFolderPage: View {
    @Environment(Settings.self) private var settings
    @Environment(LibraryStore.self) private var library

    let onAdvance: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            Text("FLACtastic")
                .font(.system(.largeTitle, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .riseFadeIn(delay: 0.0)

            VStack(spacing: Theme.Spacing.lg) {
                Text("Choose your music folder")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.textSecondary)
                    .riseFadeIn(delay: 0.08)

                Button(action: openFolder) {
                    Text("Open folder…")
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(
                            Capsule().fill(Theme.accent)
                        )
                }
                .buttonStyle(.plain)
                .riseFadeIn(delay: 0.16)

                Button(action: createEmptyFolder) {
                    Text("Create an empty folder for me")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .underline()
                }
                .buttonStyle(.plain)
                .riseFadeIn(delay: 0.22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
    }

    private func createEmptyFolder() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("flactastic", isDirectory: true)
            .appendingPathComponent("Music", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            settings.lastRootPath = dir.path
            library.openFolder(dir)
            onAdvance()
        } catch {
            print("[Onboarding] Failed to create music folder: \(error)")
        }
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
            onAdvance()
        }
    }
}
