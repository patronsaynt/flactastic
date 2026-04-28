import SwiftUI

struct ArtistGridCell: View {
    let summary: ArtistSummary
    /// Preferred image for the cell. Callers should pass the profile image
    /// when set, falling back to a banner crop, then the artwork sample.
    let preferredImage: Data?

    @Environment(Settings.self) private var settings

    private var cornerRadius: CGFloat { settings.roundedArtwork ? Theme.Radius.md : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { artwork }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .artworkShadow(size: 180)

            Text(summary.displayName)
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Text(countLabel)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private var countLabel: String {
        let releases = summary.albums.count + summary.singles.count
        let appears = summary.appearsOn.count
        if appears == 0 {
            return "\(releases) release\(releases == 1 ? "" : "s")"
        }
        return "\(releases) · appears on \(appears)"
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = preferredImage, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let data = summary.artworkSample, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Theme.surfaceElevated
                .overlay {
                    Image(systemName: "music.mic")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Theme.textTertiary.opacity(0.5))
                }
        }
    }
}
