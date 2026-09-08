import SwiftUI

/// Karaoke-style lyrics scroller. The active line is rendered large and sharp;
/// surrounding lines shrink, fade and blur away with distance, and the whole
/// stack slides as `currentTime` advances.
///
/// Lines are positioned absolutely around a centre anchor rather than stacked
/// in a `VStack` — per-line blur and scale need each row to keep its own
/// geometry, and a flow layout would reshuffle the whole column every time a
/// line's scale changed.
struct LyricsScrollerView: View {
    let lyrics: Lyrics
    let currentTime: TimeInterval
    var alignment: HorizontalAlignment = .center
    /// Size of the active line. Surrounding lines use the same face, scaled
    /// down by their distance.
    var fontSize: CGFloat = 40
    var activeStyle: AnyShapeStyle = AnyShapeStyle(Theme.textPrimary)
    /// Fraction of the container the text may occupy before wrapping.
    var maxWidthFraction: CGFloat = 0.72

    /// Vertical pitch between lines, in points.
    private let pitch: CGFloat = 74
    /// Lines rendered either side of the active one. Beyond ±4 the design's
    /// opacity curve has already reached zero.
    private let window: Int = 4

    var body: some View {
        let idx = lyrics.currentLineIndex(at: currentTime) ?? 0
        GeometryReader { geo in
            ZStack(alignment: .init(horizontal: alignment, vertical: .center)) {
                // Identity is the absolute line index, NOT the relative offset.
                // Keying on the offset would make each slot a stable view whose
                // *text* changes on every advance, so SwiftUI would cross-fade
                // the words in place instead of sliding the lines upward.
                ForEach(visibleIndices(around: idx), id: \.self) { i in
                    line(lyrics.lines[i].text, distance: i - idx, width: geo.size.width)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.85), value: idx)
        }
        .clipped()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.76),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// The lines to render, clamped to the lyric's own bounds.
    private func visibleIndices(around idx: Int) -> [Int] {
        let lower = max(0, idx - window)
        let upper = min(lyrics.lines.count - 1, idx + window)
        guard lower <= upper else { return [] }
        return Array(lower...upper)
    }

    private func line(_ text: String, distance d: Int, width: CGFloat) -> some View {
        let metrics = Self.metrics(distance: d)
        return Text(text.isEmpty ? " " : text)
            .font(.system(size: fontSize, weight: .bold))
            .tracking(-fontSize * 0.02)
            .foregroundStyle(activeStyle)
            .multilineTextAlignment(alignment == .leading ? .leading : .center)
            .frame(maxWidth: width * maxWidthFraction,
                   alignment: .init(horizontal: alignment, vertical: .center))
            .shadow(color: .black.opacity(d == 0 ? 0.6 : 0.5), radius: d == 0 ? 9 : 5, y: 2)
            // The active line picks up a soft bloom on top of the drop shadow.
            .shadow(color: .white.opacity(d == 0 ? 0.16 : 0), radius: 21)
            .scaleEffect(metrics.scale, anchor: alignment == .leading ? .leading : .center)
            .opacity(metrics.opacity)
            .blur(radius: metrics.blur)
            .offset(y: metrics.y)
    }

    /// Per-line falloff, ported from the design handoff's `lyricRows`.
    private static func metrics(distance d: Int) -> (y: CGFloat, scale: CGFloat, opacity: Double, blur: CGFloat) {
        let ad = abs(d)
        if ad == 0 {
            return (y: -8, scale: 1, opacity: 1, blur: 0)
        }
        let step = Double(ad - 1)
        return (
            y: CGFloat(d) * 74 - 8,
            scale: CGFloat(max(0.46, 0.58 - step * 0.03)),
            opacity: max(0, 0.5 - step * 0.13),
            blur: CGFloat(min(3.5, 0.6 + step * 0.8))
        )
    }
}
