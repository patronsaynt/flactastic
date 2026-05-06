import SwiftUI

struct TrackRow: View {
    let track: Track
    let isPlaying: Bool
    var displayNumber: Int? = nil
    /// When `true`, a subtle drag-handle icon is shown at the trailing edge
    /// to signal that the row can be reordered by dragging.
    var showDragHandle: Bool = false
    var showAlbumArt: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if showAlbumArt && displayNumber != nil {
                numberWithAlbumArt
            } else if showAlbumArt {
                albumArtOrIndicator
            } else {
                trackNumberOrIndicator
                    .frame(width: 28, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(isPlaying ? Theme.accent : Theme.textPrimary)
                    .lineLimit(1)

                if let artist = ArtistResolver.displayString(track.artist) {
                    Text(artist)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // File format badge
            Text(track.fileFormat.displayName)
                .font(Theme.Font.captionMono)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(Theme.surfaceElevated)
                )

            // Quality badge
            qualityBadge

            Text(FormatUtils.formatDuration(track.duration))
                .font(Theme.Font.captionMono)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()

            if showDragHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary.opacity(0.6))
                    .frame(width: 18)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var albumArtOrIndicator: some View {
        if isPlaying {
            ArtworkView(data: track.artwork, size: 36)
                .overlay(alignment: .center) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
        } else {
            ArtworkView(data: track.artwork, size: 36)
        }
    }

    @ViewBuilder
    private var numberWithAlbumArt: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Group {
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                } else if let num = displayNumber {
                    Text("\(num)")
                        .font(Theme.Font.captionMono)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 22, alignment: .trailing)

            ArtworkView(data: track.artwork, size: 36)
        }
    }

    @ViewBuilder
    private var trackNumberOrIndicator: some View {
        if isPlaying {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
        } else if let num = displayNumber ?? track.trackNumber {
            Text("\(num)")
                .font(Theme.Font.captionMono)
                .foregroundStyle(Theme.textTertiary)
        } else {
            Text("")
        }
    }

    private var qualityBadge: some View {
        let quality = AudioQuality.classify(
            sampleRate: track.sampleRate,
            bitDepth: track.bitDepth,
            format: track.fileFormat
        )
        let detail = FormatUtils.formatSampleRate(track.sampleRate, bitDepth: track.bitDepth)
        let label = detail.map { "\(quality.label) · \($0)" } ?? quality.label

        return Text(label)
            .font(Theme.Font.captionMono)
            .foregroundStyle(quality.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(quality.color.opacity(0.12))
            )
    }
}
