import SwiftUI

struct ArtistGridCell: View {
    let summary: ArtistSummary
    /// Preferred image for the cell. Callers should pass the profile image
    /// when set, falling back to a banner crop, then the artwork sample.
    let preferredImage: Data?

    @Environment(Settings.self) private var settings
    @Environment(\.displayScale) private var displayScale

    private let artSize: CGFloat = 180
    private var cornerRadius: CGFloat { settings.roundedArtwork ? Theme.Radius.md : 0 }

    /// The image source this cell should display: the preferred image when
    /// present, otherwise the artwork sample.
    private var target: (id: String, data: Data)? {
        if let d = preferredImage { return ("artist:\(summary.id)|preferred|\(d.count)", d) }
        if let d = summary.artworkSample { return ("artist:\(summary.id)|sample|\(d.count)", d) }
        return nil
    }

    /// Off-main-decoded image, tagged with the id it was decoded for so a
    /// reused cell never shows the previous artist's image. See
    /// `ArtworkView.decoded` for the pattern.
    @State private var decoded: DecodedImage? = nil
    private struct DecodedImage {
        let key: String
        let image: NSImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { artwork }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .artworkShadow(size: artSize)

            Text(summary.displayName)
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Text(countLabel)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .task(id: target?.id) {
            guard let target, resolvedImage == nil else { return }
            var box = await ArtworkImageCache.shared.thumbnailAsync(
                for: target.data, id: target.id, pointSize: artSize, scale: displayScale
            )
            // Preserve the old fallback: an undecodable preferred image
            // (corrupt data) falls through to the artwork sample.
            if box.image == nil, preferredImage != nil, let d = summary.artworkSample {
                box = await ArtworkImageCache.shared.thumbnailAsync(
                    for: d,
                    id: "artist:\(summary.id)|sample|\(d.count)",
                    pointSize: artSize,
                    scale: displayScale
                )
            }
            guard let image = box.image else { return }
            decoded = DecodedImage(key: target.id, image: image)
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

    /// Memory-only lookup in the body — the disk read / decode for cold cells
    /// happens in the `.task` above so scrolling never blocks on it.
    private var resolvedImage: NSImage? {
        guard let target else { return nil }
        if let hit = ArtworkImageCache.shared.cachedThumbnail(
            id: target.id, pointSize: artSize, scale: displayScale
        ) {
            return hit
        }
        if let decoded, decoded.key == target.id { return decoded.image }
        return nil
    }

    @ViewBuilder
    private var artwork: some View {
        if let nsImage = resolvedImage {
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
