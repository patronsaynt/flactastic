import SwiftUI
import AppKit

/// Compact mini-player shown in the popover attached to the `MenuBarExtra` item.
/// Bound to the shared `PlayerState`, so state changes in the main window are
/// reflected here and vice versa. Reuses `ArtworkView` and `SeekBarView` from
/// the main UI so look and scrubbing behaviour stay consistent.
struct MenuBarPlayerView: View {
    @Environment(PlayerState.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if player.currentTrack != nil {
                trackHeader
                SeekBarView()
                transportControls
                    .frame(maxWidth: .infinity)
            } else {
                emptyState
            }

            Divider().foregroundStyle(Theme.divider)

            footerButtons
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 320)
        .background(Theme.surface)
    }

    // MARK: - Track header

    @ViewBuilder
    private var trackHeader: some View {
        if let track = player.currentTrack {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ArtworkView(data: track.artwork, size: 72)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    if let artist = track.artist {
                        Text(artist)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if let album = track.album {
                        Text(album)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Transport

    private var transportControls: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Button { player.engine.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(MonochromeButtonStyle(size: 34))

            Button { player.engine.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(PrimaryMonochromeButtonStyle(size: 46))

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(MonochromeButtonStyle(size: 34))

            Spacer()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(Theme.textTertiary.opacity(0.6))
                .frame(width: 72, height: 72)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .fill(Theme.surfaceElevated)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing playing")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
                Text("Open FLACtastic to pick a track")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button("Open FLACtastic") {
                openMainWindow()
            }
            .buttonStyle(.plain)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.textPrimary)

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.textTertiary)
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Bring the first app window forward. `MenuBarExtra` opens its popover
        // in a borderless panel which we want to skip — pick the first window
        // that isn't the menu bar popover itself.
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            break
        }
    }
}
