import SwiftUI

struct TrackRow: View {
    let track: Track
    let isPlaying: Bool
    var displayNumber: Int? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            trackNumberOrIndicator
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(isPlaying ? Theme.accent : Theme.textPrimary)
                    .lineLimit(1)

                if let artist = track.artist {
                    Text(artist)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let badge = formatBadge {
                Text(badge)
                    .font(Theme.Font.captionMono)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(Theme.surfaceElevated)
                    )
            }

            Text(FormatUtils.formatDuration(track.duration))
                .font(Theme.Font.captionMono)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
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

    private var formatBadge: String? {
        if let rate = track.sampleRate, let bits = track.bitDepth {
            return FormatUtils.formatSampleRate(rate, bitDepth: bits)
        }
        return track.fileFormat.displayName
    }
}
