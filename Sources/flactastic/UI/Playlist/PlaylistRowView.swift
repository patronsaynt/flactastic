import SwiftUI

struct PlaylistRowView: View {
    let playlist: Playlist
    let artwork: Data?
    let trackCount: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ArtworkView(data: artwork, size: 48)

            Text(playlist.name)
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer()

            Text("\(trackCount) track\(trackCount == 1 ? "" : "s")")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(Theme.surface.opacity(0.001))
        .cornerRadius(Theme.Radius.sm)
    }
}
