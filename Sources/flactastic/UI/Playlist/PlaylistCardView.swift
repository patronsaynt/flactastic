import SwiftUI

struct PlaylistCardView: View {
    @Environment(Settings.self) private var settings

    let playlist: Playlist
    let artwork: Data?
    let trackCount: Int
    let totalDuration: TimeInterval

    /// Drives the card's rise and the artwork's highlight together.
    @State private var isHovering = false

    private var cornerRadius: CGFloat { settings.roundedArtwork ? Theme.Radius.md : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { playlistArtwork }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .artworkShadow(size: 180)
                .coverHoverHighlight(isHovering: isHovering, cornerRadius: cornerRadius)
                .padding(.bottom, 7)

            Text(playlist.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Text(FormatUtils.playlistSummary(trackCount: trackCount, duration: totalDuration))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .cardHoverLift(isHovering: isHovering)
        .onHover { isHovering = $0 }
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
