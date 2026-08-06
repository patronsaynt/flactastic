import SwiftUI
import AppKit

struct OnboardingLibraryPage: View {
    @Environment(Settings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(ListeningStore.self) private var listening
    let onNext: () -> Void

    private var folderPath: String? { settings.lastRootPath }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            OnboardingStepHeader(
                step: 2, total: 3,
                title: "Point us to your library",
                subtitle: "Choose the folder where your FLAC files live. We'll watch it for changes."
            )
            .riseFadeIn(delay: 0.0)

            Group {
                if let folderPath {
                    linkedCard(path: folderPath)
                } else {
                    dropzone
                }
            }
            .riseFadeIn(delay: 0.06)

            if folderPath == nil {
                Button("Create an empty folder for me", action: createEmptyFolder)
                    .buttonStyle(.plain)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .underline()
                    .riseFadeIn(delay: 0.1)
            }

            Button("Continue", action: onNext)
                .onboardingPrimaryButton()
                .disabled(folderPath == nil)
                .opacity(folderPath == nil ? 0.4 : 1)
                .riseFadeIn(delay: 0.14)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var dropzone: some View {
        Button(action: openFolder) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                Text("Choose Folder…")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)
                Text("or drag a folder here")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
            .background(Theme.textPrimary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.divider, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    private func linkedCard(path: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.qualityLossless.opacity(0.16))
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.qualityLossless)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Library linked")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: Theme.Spacing.md)

            Button("Change", action: openFolder)
                .buttonStyle(.plain)
                .font(Theme.Font.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.Spacing.md + 2)
        .background(Theme.qualityLossless.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(Theme.qualityLossless.opacity(0.35), lineWidth: 1)
        )
    }

    private func createEmptyFolder() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("flactastic", isDirectory: true)
            .appendingPathComponent("Music", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            adoptFolder(dir)
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
            adoptFolder(url)
        }
    }

    private func adoptFolder(_ url: URL) {
        settings.lastRootPath = url.path
        library.openFolder(url)
        playlistStore.load(from: url)
        listening.load(from: url)
    }
}
