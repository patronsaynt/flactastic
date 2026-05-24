import SwiftUI

/// Compact transport bar for the pop-out mini player. Mirrors
/// `FloatingPlayerBar`'s button cluster but with tighter sizing, slightly
/// smaller artwork, and the title/artist text below the scrubber rather
/// than to its left.
struct MiniPlayerControls: View {
    @Environment(PlayerState.self) private var player
    @Environment(MiniPlayerPresenter.self) private var presenter

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            titleRow
            transportRow
            SeekBarView()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.surface)
    }

    // MARK: - Title row (title/artist on the left, window-state controls on the right)

    private var titleRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            trackTextStack
            Spacer(minLength: Theme.Spacing.sm)
            windowControlsCluster
        }
    }

    @ViewBuilder
    private var trackTextStack: some View {
        if let track = player.currentTrack {
            VStack(alignment: .leading, spacing: 0) {
                Text(track.title)
                    .font(Theme.Font.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let artist = ArtistResolver.displayString(track.artist) {
                    Text(artist)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Nothing playing")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Queue toggle, pin (always-on-top), and return-to-main — moved into
    /// the title row so the transport buttons get the full window width.
    private var windowControlsCluster: some View {
        HStack(spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.28)) {
                    player.isQueueVisible.toggle()
                }
            } label: {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(player.isQueueVisible ? Theme.accent : Theme.textTertiary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(player.isQueueVisible ? "Hide queue" : "Show queue")

            Button {
                presenter.isPinned.toggle()
            } label: {
                Image(systemName: presenter.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(presenter.isPinned ? Theme.accent : Theme.textTertiary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(presenter.isPinned ? "Unpin from top" : "Pin to top")

            Button {
                presenter.isVisible = false
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Return to main window")
        }
    }

    // MARK: - Transport row (stretched edge-to-edge above the scrubber)

    private var transportRow: some View {
        HStack(spacing: 0) {
            transportButton(systemName: "shuffle",
                            size: 10,
                            color: player.isShuffleEnabled ? Theme.accent : Theme.textTertiary,
                            help: "Shuffle") {
                player.toggleShuffle()
            }

            transportButton(systemName: "backward.fill",
                            size: 13,
                            color: Theme.textPrimary) {
                player.engine.previous()
            }

            transportButton(systemName: player.isPlaying ? "pause.fill" : "play.fill",
                            size: 18,
                            color: Theme.textPrimary) {
                player.engine.togglePlayPause()
            }

            transportButton(systemName: "forward.fill",
                            size: 13,
                            color: Theme.textPrimary) {
                player.next()
            }

            transportButton(systemName: player.repeatMode == .one ? "repeat.1" : "repeat",
                            size: 10,
                            color: player.repeatMode != .off ? Theme.accent : Theme.textTertiary,
                            help: "Repeat") {
                switch player.repeatMode {
                case .off: player.repeatMode = .all
                case .all: player.repeatMode = .one
                case .one: player.repeatMode = .off
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Equal-width transport button that fills its share of the row so the
    /// five controls span edge-to-edge across the scrubber width.
    private func transportButton(systemName: String,
                                 size: CGFloat,
                                 color: Color,
                                 help: String? = nil,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? "")
    }
}
