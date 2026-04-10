import SwiftUI

struct NowPlayingView: View {
    @Environment(PlayerState.self) private var player

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            if let track = player.currentTrack {
                ArtworkView(data: track.artwork, size: 300)
                    .shadow(color: .white.opacity(0.05), radius: 20)

                VStack(spacing: Theme.Spacing.sm) {
                    Text(track.title)
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    if let artist = track.artist {
                        Text(artist)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    if let album = track.album {
                        Text(album)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
            } else {
                VStack(spacing: Theme.Spacing.lg) {
                    ArtworkView(data: nil, size: 240)

                    Text("Nothing playing")
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
