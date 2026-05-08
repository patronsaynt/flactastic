import SwiftUI

/// Karaoke-style line-by-line lyrics scroller. The active line is rendered
/// large and centered; surrounding lines fade and shrink with distance.
/// Lines slide up as `currentTime` advances.
struct LyricsScrollerView: View {
    let lyrics: Lyrics
    let currentTime: TimeInterval

    /// Lines visible above and below the active one. The visible window is
    /// `aboveCount + belowCount + 1` rows tall; clipping removes any that
    /// don't fit.
    private let aboveCount: Int = 2
    private let belowCount: Int = 3

    var body: some View {
        let idx = lyrics.currentLineIndex(at: currentTime) ?? 0
        VStack(spacing: 8) {
            ForEach(-aboveCount...belowCount, id: \.self) { offset in
                let i = idx + offset
                Group {
                    if lyrics.lines.indices.contains(i) {
                        let text = lyrics.lines[i].text
                        Text(text.isEmpty ? " " : text)
                            .font(offset == 0 ? Theme.Font.title : Theme.Font.bodyMedium)
                            .foregroundStyle(foreground(for: offset))
                            .scaleEffect(offset == 0 ? 1.0 : 0.92)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .id(i)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                    } else {
                        // Reserve the row so the visible window stays a
                        // consistent height even near song boundaries.
                        Color.clear.frame(height: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: idx)
    }

    private func foreground(for offset: Int) -> AnyShapeStyle {
        if offset == 0 { return AnyShapeStyle(Theme.textPrimary) }
        let fade = max(0.18, 1 - Double(abs(offset)) * 0.28)
        return AnyShapeStyle(Theme.textTertiary.opacity(fade))
    }
}
