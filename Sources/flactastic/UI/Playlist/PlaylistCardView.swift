import SwiftUI

struct PlaylistCardView: View {
    let playlist: Playlist
    let artwork: Data?
    let trackCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            playlistArtwork
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

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
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.surfaceElevated)
                .overlay {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Theme.textTertiary.opacity(0.5))
                }
        }
    }
}
