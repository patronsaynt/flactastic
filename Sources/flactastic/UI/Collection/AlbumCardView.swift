import SwiftUI

struct AlbumCardView: View {
    @Environment(Settings.self) private var settings

    let album: Album

    private var cornerRadius: CGFloat { settings.roundedArtwork ? Theme.Radius.md : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { albumArtwork }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

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
            Theme.surfaceElevated
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Theme.textTertiary.opacity(0.5))
                }
        }
    }
}
