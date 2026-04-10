import SwiftUI

struct TransportControlsView: View {
    @Environment(PlayerState.self) private var player

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            SeekBarView()
                .padding(.horizontal, Theme.Spacing.xl)

            HStack(spacing: Theme.Spacing.xl) {
                VolumeSliderView()

                Spacer()

                HStack(spacing: Theme.Spacing.lg) {
                    Button { player.engine.previous() } label: {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(MonochromeButtonStyle())

                    Button { player.engine.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(PrimaryMonochromeButtonStyle())

                    Button { player.engine.next() } label: {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(MonochromeButtonStyle())
                }

                Spacer()

                nowPlayingMini
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
        .padding(.vertical, Theme.Spacing.md)
        .background(
            Theme.surface
                .overlay(alignment: .top) {
                    Theme.divider.frame(height: 0.5)
                }
        )
    }

    @ViewBuilder
    private var nowPlayingMini: some View {
        if let track = player.currentTrack {
            HStack(spacing: Theme.Spacing.sm) {
                ArtworkView(data: track.artwork, size: 36)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(track.title)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let artist = track.artist {
                        Text(artist)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 160, alignment: .trailing)
        } else {
            Color.clear.frame(width: 160)
        }
    }
}
