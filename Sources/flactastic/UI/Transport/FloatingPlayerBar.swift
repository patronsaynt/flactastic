import SwiftUI

struct FloatingPlayerBar: View {
    @Environment(PlayerState.self) private var player
    @Environment(Settings.self) private var settings

    var body: some View {
        if player.currentTrack != nil {
            playerContent
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .fill(Theme.surface)
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                )
        }
    }

    private var playerContent: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                // Center: transport controls (centered to full bar width)
                transportControls

                // Left: track info / Right: volume pinned to edges
                HStack {
                    trackInfo
                    Spacer(minLength: 0)
                    VolumeSliderView()
                }
            }

            SeekBarView()
        }
    }

    // MARK: - Track Info

    @ViewBuilder
    private var trackInfo: some View {
        if let track = player.currentTrack {
            HStack(spacing: Theme.Spacing.sm) {
                ArtworkView(data: track.artwork, size: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(Theme.Font.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let artist = track.artist {
                        Text(artist)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 150, alignment: .leading)
            }
        }
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 11))
                    .foregroundStyle(player.isShuffleEnabled ? Theme.accent : Theme.textTertiary)
            }
            .buttonStyle(.plain)

            Button { player.engine.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(MonochromeButtonStyle(size: 30))

            Button { player.engine.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(PrimaryMonochromeButtonStyle(size: 42))

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(MonochromeButtonStyle(size: 30))

            Button {
                switch player.repeatMode {
                case .off: player.repeatMode = .all
                case .all: player.repeatMode = .one
                case .one: player.repeatMode = .off
                }
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 11))
                    .foregroundStyle(player.repeatMode != .off ? Theme.accent : Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }
}
