import SwiftUI

/// Library-derived audio-fidelity panel (formerly "Studio Quality Index").
/// Recomputes from `library.tracks` on every change, so the format donut,
/// bit-depth bars, and sample-rate list only ever show values present in the
/// current library.
struct FidelidexView: View {
    @Environment(LibraryStore.self) private var library

    private var fidelity: LibraryFidelity { LibraryFidelity(tracks: library.tracks) }

    var body: some View {
        let f = fidelity
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header(score: f.score)

            if f.isEmpty {
                Text("No audio files in your library yet.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                // Use an adaptive grid so the three cards wrap gracefully.
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    formatCard(f)
                    bitDepthCard(f)
                    sampleRateCard(f)
                }
            }
        }
    }

    // MARK: - Header

    private func header(score: Int) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FIDELIDEX")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textSecondary)
                Text("Audio fidelity breakdown across your library")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            HStack(spacing: 7) {
                Text("SCORE")
                    .font(.system(size: 10)).tracking(1)
                    .foregroundStyle(Theme.textTertiary)
                Text("\(score)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.qualityLossless)
                    .monospacedDigit()
                Text("/ 100")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(Theme.divider))
        }
    }

    // MARK: - Format donut card

    private func formatCard(_ f: LibraryFidelity) -> some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                Text("File Format Distribution")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(f.totalFiles.formatted()) total files")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 3)

                HStack(spacing: 18) {
                    FormatDonut(slices: f.formats)
                        .frame(width: 116, height: 116)
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(f.formats.enumerated()), id: \.element.id) { idx, slice in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(idx == 0 ? Theme.qualityLossless
                                                   : Theme.textPrimary.opacity(donutOpacity(idx)))
                                    .frame(width: 7, height: 7)
                                Text(slice.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 38, alignment: .leading)
                                Text(percent(slice.fraction))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textTertiary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    Spacer(minLength: 12)

                    VStack(spacing: 10) {
                        miniStat(value: percent(f.losslessFraction), label: "Lossless",
                                 tint: Theme.textPrimary)
                        miniStat(value: f.hiResCount.formatted(), label: "Hi-Res files",
                                 tint: Theme.qualityLossless)
                    }
                    .frame(width: 120)
                }
                .padding(.top, 16)

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Bit depth card

    private func bitDepthCard(_ f: LibraryFidelity) -> some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                Text("Bit Depth")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 16)

                if f.depths.isEmpty {
                    Text("No bit-depth metadata")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    // Single segmented bar: one proportional slice per depth.
                    SegmentedBar(
                        segments: f.depths.enumerated().map { idx, depth in
                            (depth.fraction, depthColor(idx))
                        }
                    )
                    .frame(height: 14)
                    .padding(.bottom, 14)

                    // Legend
                    HStack(spacing: 16) {
                        ForEach(Array(f.depths.enumerated()), id: \.element.id) { idx, depth in
                            HStack(spacing: 6) {
                                Circle().fill(depthColor(idx)).frame(width: 7, height: 7)
                                Text("\(depth.bits)-bit")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                Text(percent(depth.fraction))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Sample rate card

    private func sampleRateCard(_ f: LibraryFidelity) -> some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sample Rates")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 16)

                VStack(spacing: 11) {
                    ForEach(Array(f.rates.enumerated()), id: \.element.id) { idx, rate in
                        HStack(spacing: 11) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rate.label)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)
                                Text(rate.tier)
                                    .font(.system(size: 8))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .frame(width: 58, alignment: .leading)
                            ProgressBar(
                                fraction: rate.fraction,
                                tint: idx == 0 ? Theme.qualityLossless : Theme.textPrimary.opacity(0.5),
                                height: 3
                            )
                            Text(rate.count.formatted())
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textTertiary)
                                .monospacedDigit()
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Building blocks

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.divider))
    }

    private func miniStat(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 9)).tracking(1)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.divider))
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private func donutOpacity(_ idx: Int) -> Double {
        let steps = [0.32, 0.20, 0.55, 0.42, 0.30, 0.24]
        return steps[(idx - 1).clamped(to: 0..<steps.count)]
    }

    /// Shared tint for a bit-depth segment/legend dot: the accent for the most
    /// common depth, then descending monochrome shades for the rest.
    private func depthColor(_ idx: Int) -> Color {
        idx == 0 ? Theme.qualityLossless : Theme.textPrimary.opacity(donutOpacity(idx))
    }
}

// MARK: - Segmented bar

/// A single horizontal bar split into proportional, rounded segments that fill
/// the available width exactly. Fractions are expected to sum to ~1.
private struct SegmentedBar: View {
    let segments: [(fraction: Double, color: Color)]

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let gaps = CGFloat(max(segments.count - 1, 0)) * spacing
            let available = max(0, geo.size.width - gaps)
            HStack(spacing: spacing) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    Capsule()
                        .fill(seg.color)
                        .frame(width: available * CGFloat(min(max(seg.fraction, 0), 1)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Donut

private struct FormatDonut: View {
    let slices: [LibraryFidelity.FormatSlice]

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.divider, lineWidth: 11)
            ForEach(Array(slicesWithOffsets.enumerated()), id: \.offset) { idx, item in
                Circle()
                    .trim(from: item.start, to: item.end)
                    .stroke(
                        idx == 0 ? Theme.qualityLossless : Theme.textPrimary.opacity(opacity(idx)),
                        style: StrokeStyle(lineWidth: 11, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }
            if let top = slices.first {
                VStack(spacing: 0) {
                    Text("\(Int((top.fraction * 100).rounded()))%")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Text(top.name.uppercased())
                        .font(.system(size: 8)).tracking(1)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private var slicesWithOffsets: [(start: CGFloat, end: CGFloat)] {
        var result: [(CGFloat, CGFloat)] = []
        var cursor: CGFloat = 0
        for slice in slices {
            let end = cursor + CGFloat(slice.fraction)
            result.append((cursor, min(end, 1)))
            cursor = end
        }
        return result
    }

    private func opacity(_ idx: Int) -> Double {
        let steps = [0.32, 0.20, 0.55, 0.42, 0.30, 0.24]
        return steps[(idx - 1).clamped(to: 0..<steps.count)]
    }
}

// MARK: - Shared progress bar

struct ProgressBar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.divider)
                Capsule().fill(tint)
                    .frame(width: max(0, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: height)
    }
}

private extension Int {
    func clamped(to range: Range<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound - 1)
    }
}
