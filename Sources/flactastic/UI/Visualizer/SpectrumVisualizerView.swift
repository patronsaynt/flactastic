import SwiftUI
import AppKit

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
        return HStack(alignment: .center, spacing: Theme.Spacing.xl) {
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
                    font: .system(size: 17, weight: .semibold),
                    foregroundStyle: AnyShapeStyle(Theme.textSecondary)
                )
                if let album, !album.isEmpty {
                    MarqueeText(
                        text: album,
                        font: .system(size: 13),
                        foregroundStyle: AnyShapeStyle(Theme.textTertiary)
                    )
                }
                TechSpecLabel(track: track)
                    .padding(.top, Theme.Spacing.sm)
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.xxl)
    }

    // MARK: - Horizontal: spectrum above, details below.

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
                    font: .system(size: 13, weight: .medium),
                    foregroundStyle: AnyShapeStyle(Theme.textSecondary)
                )
                if let album, !album.isEmpty {
                    MarqueeText(
                        text: album,
                        font: .system(size: 11),
                        foregroundStyle: AnyShapeStyle(Theme.textTertiary)
                    )
                }
                TechSpecLabel(track: track)
                    .padding(.top, Theme.Spacing.sm)
            }

            Spacer(minLength: 0)

            PlaybackTimeReadout()
        }
    }

    // MARK: - Spectrogram: full-canvas stipple with corner chrome.

    private var spectrogramLayout: some View {
        let track = player.currentTrack
        let artist = ArtistResolver.displayString(track?.artist) ?? "Unknown Artist"
        return ZStack {
            SpectrogramStipple(magnitudes: analyzer.magnitudes)

            LinearGradient(
                colors: [Theme.background.opacity(0),
                         Theme.background.opacity(0.72),
                         Theme.background.opacity(0.9)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 120)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            HStack(spacing: 14) {
                Text("\(track?.title ?? "—") — \(artist)")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1.5)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 28, height: 1)
                PlaybackTimeReadout(showsTotal: false, size: 11)
            }
            .padding(.leading, Theme.Spacing.xxl)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .allowsHitTesting(false)

        }
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

                for radius in [inner - 10, inner + maxBar + 14] {
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .color(VisualizerPalette.guideRing),
                        lineWidth: 1
                    )
                }

                // Mirrored spokes: the low bins run down one half of the
                // circle and back up the other, so the figure is symmetric
                // instead of seaming at 12 o'clock.
                let spokes = count * 2
                for i in 0..<spokes {
                    let mag = CGFloat(magnitudes[i < count ? i : spokes - 1 - i])
                    let angle = (Double(i) / Double(spokes)) * .pi * 2 - .pi / 2
                    let length = inner + maxBar * mag
                    let cosA = cos(angle), sinA = sin(angle)
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + cosA * inner,
                                          y: center.y + sinA * inner))
                    path.addLine(to: CGPoint(x: center.x + cosA * length,
                                             y: center.y + sinA * length))
                    ctx.stroke(
                        path,
                        with: .color(VisualizerPalette.mark.opacity(0.35 + Double(mag) * 0.6)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                }
            }
        }
    }
}

// MARK: - Horizontal

private struct HorizontalSpectrum: View {
    let magnitudes: [Float]

    /// Height reserved below the baseline for the reflection stubs. The
    /// prototype draws these starting at the canvas' own bottom edge, where
    /// the browser clips them away entirely — reserving the strip is what
    /// makes the footing it clearly intends actually visible.
    private static let reflectionHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let barCount = max(magnitudes.count, 1)
            let barSpacing: CGFloat = 4
            let barWidth = max(2, (geo.size.width - barSpacing * CGFloat(barCount - 1)) / CGFloat(barCount))
            let baselineY = geo.size.height - Self.reflectionHeight

            Canvas { ctx, _ in
                for i in 0..<barCount {
                    let mag = CGFloat(magnitudes[i])
                    let h = max(2, mag * baselineY)
                    let x = CGFloat(i) * (barWidth + barSpacing)

                    ctx.fill(
                        Path(roundedRect: CGRect(x: x, y: baselineY - h, width: barWidth, height: h),
                             cornerRadius: barWidth / 2),
                        with: .color(VisualizerPalette.mark.opacity(0.42 + Double(mag) * 0.53))
                    )
                    ctx.fill(
                        Path(roundedRect: CGRect(x: x, y: baselineY,
                                                 width: barWidth,
                                                 height: min(Self.reflectionHeight, h * 0.35)),
                             cornerRadius: barWidth / 2),
                        with: .color(VisualizerPalette.mark.opacity(0.14))
                    )
                }

                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: baselineY))
                baseline.addLine(to: CGPoint(x: geo.size.width, y: baselineY))
                ctx.stroke(baseline, with: .color(Theme.divider), lineWidth: 1)
            }
        }
    }
}

// MARK: - Spectrogram

/// Scrolling stipple spectrogram.
///
/// The history lives in a persistent bitmap used as a horizontal ring buffer:
/// each frame stipples a single fresh column at the write head and the head
/// wraps around, so nothing ever moves. Display then draws that bitmap twice,
/// offset so the newest column lands on the right edge and the seam falls off
/// the left.
///
/// The design prototype instead blits the whole surface one step to the left
/// each frame. That is a full-surface copy per frame on top of the one the
/// display already needs — around 18 MB of memcpy at 60 Hz on a Retina
/// window — which is exactly the sort of steady cost that reads as stutter.
/// The ring buffer produces the identical image for none of it.
private struct SpectrogramStipple: NSViewRepresentable {
    let magnitudes: [Float]

    func makeNSView(context: Context) -> StippleView { StippleView() }

    func updateNSView(_ view: StippleView, context: Context) {
        view.append(magnitudes)
    }

    final class StippleView: NSView {
        /// Horizontal advance per frame, in points.
        private static let step: CGFloat = 1.6

        private var buffer: CGContext?
        private var bufferSize: CGSize = .zero
        private var bufferScale: CGFloat = 1
        private var bufferIsDark: Bool = true
        /// Write head, in points from the buffer's left edge.
        private var head: CGFloat = 0
        /// Guards against advancing the scroll on re-renders the analyzer
        /// didn't cause — the chrome overlaid on this view redraws on every
        /// playback-time tick, which would otherwise double the scroll rate.
        private var lastMagnitudes: [Float] = []

        /// Stipple one fresh column at the write head, then advance it.
        func append(_ mags: [Float]) {
            guard !mags.isEmpty, bounds.width > 1, bounds.height > 1,
                  mags != lastMagnitudes else { return }
            lastMagnitudes = mags

            let scale = window?.backingScaleFactor ?? 2
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if buffer == nil || bufferSize != bounds.size
                || bufferScale != scale || bufferIsDark != isDark {
                makeBuffer(size: bounds.size, scale: scale, isDark: isDark)
            }
            guard let ctx = buffer else { return }

            let w = bounds.width, h = bounds.height
            head += Self.step
            if head >= w { head -= w }

            // Wipe the strip about to be written, including the part that
            // wraps past the right edge.
            ctx.clear(CGRect(x: head, y: 0, width: Self.step, height: h))
            let overshoot = head + Self.step - w
            if overshoot > 0 {
                ctx.clear(CGRect(x: 0, y: 0, width: overshoot, height: h))
            }

            let rows = mags.count
            let rowHeight = h / CGFloat(rows)
            let base: NSColor = isDark ? .white : .black

            for i in 0..<rows {
                let mag = CGFloat(mags[i])
                guard mag >= 0.05 else { continue }
                // Bin 0 is the lowest frequency and sits at the bottom. The
                // 0.94 squeeze plus a 14pt inset keeps the extremes clear of
                // the chrome overlaid on top.
                let bandTop = CGFloat(i + 1) * rowHeight * 0.94 + 14
                let radius = max(0.6, mag * 1.6)
                ctx.setFillColor(base.withAlphaComponent(0.12 + mag * 0.6).cgColor)
                for _ in 0..<(1 + Int((mag * 4).rounded())) {
                    var dotX = head + CGFloat.random(in: 0..<Self.step)
                    if dotX >= w { dotX -= w }
                    let dotY = bandTop - CGFloat.random(in: 0..<rowHeight)
                    ctx.fillEllipse(in: CGRect(x: dotX - radius, y: dotY - radius,
                                               width: radius * 2, height: radius * 2))
                }
            }
            needsDisplay = true
        }

        private func makeBuffer(size: CGSize, scale: CGFloat, isDark: Bool) {
            let pixelWidth = Int(size.width * scale), pixelHeight = Int(size.height * scale)
            guard pixelWidth > 0, pixelHeight > 0 else { return }
            let ctx = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            ctx?.scaleBy(x: scale, y: scale)
            buffer = ctx
            bufferSize = size
            bufferScale = scale
            bufferIsDark = isDark
            head = 0
        }

        /// Two draws of the same bitmap, shifted so the write head sits at the
        /// right edge; whichever copy covers a given pixel wins.
        override func draw(_ dirtyRect: NSRect) {
            guard let image = buffer?.makeImage(),
                  let ctx = NSGraphicsContext.current?.cgContext else { return }
            let w = bounds.width, h = bounds.height
            let dx = w - (head + Self.step)
            ctx.draw(image, in: CGRect(x: dx, y: 0, width: w, height: h))
            ctx.draw(image, in: CGRect(x: dx - w, y: 0, width: w, height: h))
        }
    }
}
