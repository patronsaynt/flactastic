import SwiftUI

struct AlbumRowView: View {
    let album: Album

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ArtworkView(data: album.artwork, size: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(album.artist ?? "Unknown Artist")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(album.trackCount) tracks")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)

            Text(FormatUtils.formatDuration(album.totalDuration))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(Theme.surface.opacity(0.001)) // hit target
        .cornerRadius(Theme.Radius.sm)
    }
}
