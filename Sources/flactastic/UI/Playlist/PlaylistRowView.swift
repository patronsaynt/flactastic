import SwiftUI

struct PlaylistRowView: View {
    let playlist: Playlist
    let artwork: Data?
    let trackCount: Int
    let totalDuration: TimeInterval

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(data: artwork, size: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text("\(trackCount) track\(trackCount == 1 ? "" : "s")")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.md)

            Text(FormatUtils.coarseDuration(totalDuration))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)
        }
        .flRowStyle()
    }
}
