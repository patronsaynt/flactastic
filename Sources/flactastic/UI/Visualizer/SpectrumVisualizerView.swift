import SwiftUI

struct SpectrumVisualizerView: View {
    @Environment(PlayerState.self) private var player
    let mode: VisualizerMode
    let analyzer: SpectrumAnalyzer

    var body: some View {
        Group {
            switch mode {
            case .spectrumRadial:      radialLayout
            case .spectrumHorizontal:  horizontalLayout
            case .spectrogram:         spectrogramLayout
            default:                   EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Radial: details on the left, radial spectrum on the right.

    private var radialLayout: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                radialDetails(maxWidth: geo.size.width * 0.45)
                    .frame(width: geo.size.width * 0.5)

                RadialSpectrum(magnitudes: analyzer.magnitudes)
                    .padding(Theme.Spacing.xl)
                    .frame(width: geo.size.width * 0.5,
                           height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func radialDetails(maxWidth: CGFloat) -> some View {
        let track = player.currentTrack
        let artist = ArtistResolver.displayString(track?.artist) ?? "Unknown Artist"
        let album = track?.album?.trimmingCharacters(in: .whitespaces)
        return HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            ArtworkView(data: track?.artwork, size: 140)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                MarqueeText(
                    text: track?.title ?? "—",
                    font: .system(size: 30),
                    weight: .bold,
                    foregroundStyle: AnyShapeStyle(Theme.textPrimary)
                )
                MarqueeText(
                    text: artist,
                    font: Theme.Font.title,
                    foregroundStyle: AnyShapeStyle(Theme.textSecondary)
                )
                if let album, !album.isEmpty {
                    MarqueeText(
                        text: album,
                        font: Theme.Font.body,
                        foregroundStyle: AnyShapeStyle(Theme.textTertiary)
                    )
                }
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.xxl)
    }

    // MARK: - Horizontal: spectrum across the top half, details below
    // (artwork left, text right — Monstercat-style).

    private var horizontalLayout: some View {
        VStack(spacing: Theme.Spacing.xl) {
            HorizontalSpectrum(magnitudes: analyzer.magnitudes)
                .frame(height: 200)

            horizontalDetails
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var horizontalDetails: some View {
        let track = player.currentTrack
        let artist = ArtistResolver.displayString(track?.artist) ?? "Unknown Artist"
        let album = track?.album?.trimmingCharacters(in: .whitespaces)
        return HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            ArtworkView(data: track?.artwork, size: 96)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: track?.title ?? "—",
                    font: .system(size: 22),
                    weight: .semibold,
                    foregroundStyle: AnyShapeStyle(Theme.textPrimary)
                )
                MarqueeText(
                    text: artist,
                    font: Theme.Font.bodyMedium,
                    foregroundStyle: AnyShapeStyle(Theme.textSecondary)
                )
                if let album, !album.isEmpty {
                    MarqueeText(
                        text: album,
                        font: Theme.Font.caption,
                        foregroundStyle: AnyShapeStyle(Theme.textTertiary)
                    )
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Spectrogram: full-canvas heatmap with a small details header.

    private var spectrogramLayout: some View {
        SpectrogramView(history: analyzer.spectrogramHistory)
    }
}

// MARK: - Radial

private struct RadialSpectrum: View {
    let magnitudes: [Float]

    var body: some View {
        GeometryReader { geo in
            let minSide = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            // Keep total radius (inner + maxBar) ≤ minSide / 2 so the bars
            // never spill past the visualizer canvas at any aspect ratio.
            let inner = minSide * 0.24
            let maxBar = minSide * 0.13

            Canvas { ctx, _ in
                let count = magnitudes.count
                guard count > 0 else { return }
                for i in 0..<count {
                    let angle = (Double(i) / Double(count)) * .pi * 2 - .pi / 2
                    let mag = CGFloat(magnitudes[i])
                    let length = inner + maxBar * mag
                    let cosA = cos(angle), sinA = sin(angle)
                    let p0 = CGPoint(x: center.x + cosA * inner,
                                     y: center.y + sinA * inner)
                    let p1 = CGPoint(x: center.x + cosA * length,
                                     y: center.y + sinA * length)
                    var path = Path()
                    path.move(to: p0)
                    path.addLine(to: p1)
                    ctx.stroke(path,
                               with: .color(Theme.accent.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }

        }
    }
}

// MARK: - Horizontal

private struct HorizontalSpectrum: View {
    let magnitudes: [Float]

    var body: some View {
        GeometryReader { geo in
            let count = magnitudes.count
            let barCount = max(count, 1)
            let barSpacing: CGFloat = 4
            let barWidth = max(2, (geo.size.width - barSpacing * CGFloat(barCount - 1)) / CGFloat(barCount))
            let baselineY = geo.size.height
            let maxBar = geo.size.height

            Canvas { ctx, _ in
                for i in 0..<barCount {
                    let mag = CGFloat(magnitudes[i])
                    let h = max(2, mag * maxBar)
                    let x = CGFloat(i) * (barWidth + barSpacing)
                    let rect = CGRect(x: x, y: baselineY - h, width: barWidth, height: h)
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    ctx.fill(path, with: .color(Theme.textSecondary.opacity(0.85)))
                }
            }
        }
    }
}

// MARK: - Spectrogram

private struct SpectrogramView: View {
    let history: [[Float]]

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, _ in
                guard !history.isEmpty else { return }
                let cols = history.count
                let rows = history.first?.count ?? 0
                guard rows > 0 else { return }
                let colW = geo.size.width / CGFloat(cols)
                let rowH = geo.size.height / CGFloat(rows)
                for c in 0..<cols {
                    let frame = history[c]
                    for r in 0..<rows {
                        let mag = CGFloat(frame[r])
                        guard mag > 0.02 else { continue }
                        let color = heatColor(for: mag)
                        let rect = CGRect(
                            x: CGFloat(c) * colW,
                            y: geo.size.height - CGFloat(r + 1) * rowH,
                            width: colW + 0.5,
                            height: rowH + 0.5
                        )
                        ctx.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
    }

    private func heatColor(for v: CGFloat) -> Color {
        let t = max(0, min(1, v))
        if t < 0.5 {
            let k = t / 0.5
            return Color(
                red:   0.0 * (1 - k) + 0.3 * k,
                green: 0.9 * (1 - k) + 0.85 * k,
                blue:  0.8 * (1 - k) + 0.4 * k
            ).opacity(0.55 + 0.45 * t)
        } else {
            let k = (t - 0.5) / 0.5
            return Color(
                red:   0.3 * (1 - k) + 0.95 * k,
                green: 0.85 * (1 - k) + 0.75 * k,
                blue:  0.4 * (1 - k) + 0.2 * k
            ).opacity(0.7 + 0.3 * t)
        }
    }
}
