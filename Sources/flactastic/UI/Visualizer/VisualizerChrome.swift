import SwiftUI
import AppKit

/// Shared chrome for the visualizer modes: the theme-adaptive palette, the
/// tech-spec caption, the glowing progress bar and the film-grain overlay.
///
/// The Claude Design handoff is dark-only — it hardcodes `#ffffff` marks on a
/// `#000000` canvas. FLACtastic has a light theme, so every one of those
/// hardcoded values is re-expressed here as an adaptive pair. The design's
/// *alpha ramps* are preserved verbatim; only the base hue flips.
enum VisualizerPalette {

    /// The colour every generated mark is drawn in — spectrum bars,
    /// spectrogram stipple, wheel sparkles. White on dark, black on light.
    static let mark = Color(nsColor: adaptive(dark: .white, light: .black))

    /// Faint guide geometry (the radial spectrum's two rings).
    static var guideRing: Color { mark.opacity(0.10) }

    /// Full-canvas dim behind the mode wheel. The design darkens with
    /// `brightness(0.55)`; in light mode we lighten instead so the wheel's
    /// dark text keeps its contrast.
    static let scrim = Color(nsColor: adaptive(
        dark:  NSColor(white: 0, alpha: 0.45),
        light: NSColor(white: 1, alpha: 0.55)
    ))

    /// The wheel panel's leading wash — opaque at the edge, clear at 100%.
    static var panelWash: [Color] {
        let base = Color(nsColor: adaptive(dark: .black, light: .white))
        return [base.opacity(0.92), base.opacity(0.78), base.opacity(0)]
    }

    /// Hairline down the panel's leading edge.
    static var panelEdge: Color { mark.opacity(0.22) }

    /// Unselected wheel rows.
    static var wheelUnselected: Color { mark.opacity(0.42) }

    /// The dip in the selected row's shimmer sweep.
    static var shimmerDip: Color { mark.opacity(0.45) }

    private static func adaptive(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

// MARK: - Tech spec caption

/// `FLAC · 24-BIT / 96 kHz` — the uppercase fidelity caption the handoff puts
/// under the track details in every details-bearing mode. Renders nothing when
/// the track carries no format or rate metadata at all.
struct TechSpecLabel: View {
    let track: Track?
    /// Lyrics draws its chrome white-on-photo rather than in theme colours.
    var style: AnyShapeStyle = AnyShapeStyle(Theme.textTertiary)

    var body: some View {
        if let spec = FormatUtils.techSpec(for: track) {
            Text(spec)
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.5)
                .foregroundStyle(style)
                .lineLimit(1)
        }
    }
}

// MARK: - Progress

/// The handoff's 3pt progress bar: a divider-toned track with an accent fill
/// that carries a soft bloom (`0 0 10px rgba(255,255,255,0.45)`).
struct GlowProgressBar: View {
    let fraction: Double
    var track: Color = Theme.divider
    var fill: Color = Theme.accent
    var glow: Bool = true

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track).frame(height: 3)
                Capsule()
                    .fill(fill)
                    .frame(width: g.size.width * CGFloat(max(0, min(1, fraction))),
                           height: 3)
                    .shadow(color: glow ? fill.opacity(0.45) : .clear, radius: 5)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 3)
    }
}

// MARK: - Film grain

/// Tiling monochrome noise, generated once and reused. Matches the handoff's
/// inline `feTurbulence` overlay on the Lyrics backdrop.
///
/// Deliberately composited normally rather than with `.blendMode(.overlay)`:
/// a blend mode forces the whole window into an offscreen pass on every
/// frame, and at this opacity the two are near-indistinguishable over a dark
/// ground. The noise is centred on mid-grey so a plain composite darkens and
/// lightens in roughly equal measure instead of just washing the image out.
struct VisualizerFilmGrain: View {
    var opacity: Double = 0.10

    var body: some View {
        Image(nsImage: Self.tile)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .allowsHitTesting(false)
    }

    /// 128×128 of white noise. Rendered on first access and cached for the
    /// lifetime of the process — regenerating per frame would be absurd.
    private static let tile: NSImage = makeTile(side: 128)

    private static func makeTile(side: Int) -> NSImage {
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * side)
        var generator = SystemRandomNumberGenerator()
        for i in stride(from: 0, to: pixels.count, by: 4) {
            // Narrow band around mid-grey — full-range noise reads as static
            // rather than grain once it is composited normally.
            let v = UInt8.random(in: 96...160, using: &generator)
            pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v
            pixels[i + 3] = 255
        }
        let image = NSImage(size: NSSize(width: side, height: side))
        pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let cg = ctx.makeImage() else { return }
            image.addRepresentation(NSBitmapImageRep(cgImage: cg))
        }
        return image
    }
}

// MARK: - Playback-driven chrome

/// `PlayerState.currentTime` is republished 20×/s for the whole of playback,
/// and `@Observable` invalidates every view that *reads* it. When a mode's
/// body reads it directly — even just to size a progress bar — the entire mode
/// re-evaluates and AppKit re-lays-out the hosting view 20 times a second,
/// artwork, marquees and all. That baseline cost is what makes a mode
/// cross-fade stutter, because the transition is competing with it.
///
/// These two views exist to own that dependency. They read the clock
/// themselves, so the surrounding mode body never touches `currentTime` and
/// only this small subtree is invalidated per tick.

/// The 3pt progress bar, optionally flanked by monospaced elapsed / total.
struct PlaybackProgressBar: View {
    @Environment(PlayerState.self) private var player

    var showsLabels: Bool = false
    var track: Color = Theme.divider
    var fill: Color = Theme.accent
    var glow: Bool = true
    var labelStyle: AnyShapeStyle = AnyShapeStyle(Theme.textTertiary)

    var body: some View {
        let total = player.duration ?? 0
        let fraction = total > 0 ? player.currentTime / total : 0
        HStack(spacing: Theme.Spacing.md) {
            if showsLabels {
                label(FormatUtils.formatDuration(player.currentTime))
            }
            GlowProgressBar(fraction: fraction, track: track, fill: fill, glow: glow)
            if showsLabels {
                label(FormatUtils.formatDuration(total > 0 ? total : nil))
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(labelStyle)
    }
}

/// A standalone `0:42 / 3:15` readout.
struct PlaybackTimeReadout: View {
    @Environment(PlayerState.self) private var player

    var showsTotal: Bool = true
    var size: CGFloat = 13
    var style: AnyShapeStyle = AnyShapeStyle(Theme.textTertiary)

    var body: some View {
        let total = player.duration ?? 0
        let elapsed = FormatUtils.formatDuration(player.currentTime)
        Text(showsTotal
             ? "\(elapsed) / \(FormatUtils.formatDuration(total > 0 ? total : nil))"
             : elapsed)
            .font(.system(size: size, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(style)
            .fixedSize()
    }
}
