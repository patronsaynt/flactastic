import SwiftUI

struct PlaylistCardView: View {
    @Environment(Settings.self) private var settings

    let playlist: Playlist
    let artwork: Data?
    let trackCount: Int

    private var cornerRadius: CGFloat { settings.roundedArtwork ? Theme.Radius.md : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { playlistArtwork }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .artworkShadow(size: 180)

            Text(playlist.name)
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Text("\(trackCount) track\(trackCount == 1 ? "" : "s")")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var playlistArtwork: some View {
        if let data = artwork, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Theme.surfaceElevated
                .overlay {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Theme.textTertiary.opacity(0.5))
                }
        }
    }
}
