import SwiftUI

struct FloatingPlayerBar: View {
    @Environment(PlayerState.self) private var player
    @Environment(Settings.self) private var settings

    var body: some View {
        if player.currentTrack != nil {
            playerContent
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .fill(Theme.surface)
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                )
        }
    }

    private var playerContent: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.lg) {
                // Left: artwork + track info
                trackInfo

                Spacer()

                // Center: transport controls
                transportControls

                Spacer()

                // Right: volume
                VolumeSliderView()
            }

            // Seek bar below
            SeekBarView()
        }
    }

    // MARK: - Track Info

    @ViewBuilder
    private var trackInfo: some View {
        if let track = player.currentTrack {
            HStack(spacing: Theme.Spacing.md) {
                ArtworkView(data: track.artwork, size: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let artist = track.artist {
                        Text(artist)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 200, alignment: .leading)
            }
        }
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: Theme.Spacing.lg) {
            // Shuffle
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 13))
                    .foregroundStyle(player.isShuffleEnabled ? Theme.accent : Theme.textTertiary)
            }
            .buttonStyle(.plain)

            // Previous
            Button { player.engine.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(MonochromeButtonStyle())

            // Play/Pause
            Button { player.engine.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(PrimaryMonochromeButtonStyle())

            // Next
            Button { player.engine.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(MonochromeButtonStyle())

            // Repeat
            Button {
                switch player.repeatMode {
                case .off: player.repeatMode = .all
                case .all: player.repeatMode = .one
                case .one: player.repeatMode = .off
                }
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 13))
                    .foregroundStyle(player.repeatMode != .off ? Theme.accent : Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }
}
