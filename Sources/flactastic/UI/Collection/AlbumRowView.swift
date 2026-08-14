import SwiftUI

struct AlbumRowView: View {
    let album: Album

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(data: album.artwork, size: 46, id: "album:\(album.id)")

            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(album.isCompilation
                     ? "Compilation"
                     : (ArtistResolver.displayString(album.artist) ?? "Unknown Artist"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.md)

            Text("\(album.trackCount) track\(album.trackCount == 1 ? "" : "s")")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)

            Text(FormatUtils.formatDuration(album.totalDuration))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)
        }
        .flRowStyle()
    }
}
