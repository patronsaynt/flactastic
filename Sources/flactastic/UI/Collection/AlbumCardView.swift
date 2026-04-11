import SwiftUI

struct AlbumCardView: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            albumArtwork
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            Text(album.name)
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Text(album.artist ?? "Unknown Artist")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var albumArtwork: some View {
        if let data = album.artwork, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.surfaceElevated)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Theme.textTertiary.opacity(0.5))
                }
        }
    }
}
