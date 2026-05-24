import SwiftUI

/// Karaoke-style line-by-line lyrics scroller. The active line is rendered
/// large and centered; surrounding lines fade and shrink with distance.
/// Lines slide up as `currentTime` advances.
struct LyricsScrollerView: View {
    let lyrics: Lyrics
    let currentTime: TimeInterval
    var alignment: HorizontalAlignment = .center
    var activeFont: Font = Theme.Font.title
    var inactiveFont: Font = Theme.Font.bodyMedium
    /// Foreground style for the active line; surrounding lines fade tinted
    /// versions of this. Defaults to the regular primary text colour.
    var activeStyle: AnyShapeStyle = AnyShapeStyle(Theme.textPrimary)
    var inactiveStyle: AnyShapeStyle = AnyShapeStyle(Theme.textTertiary)

    /// Lines visible above and below the active one. The visible window is
    /// `aboveCount + belowCount + 1` rows tall; clipping removes any that
    /// don't fit.
    private let aboveCount: Int = 2
    private let belowCount: Int = 3

    var body: some View {
        let idx = lyrics.currentLineIndex(at: currentTime) ?? 0
        let textAlignment: TextAlignment = {
            switch alignment {
            case .leading:  return .leading
            case .trailing: return .trailing
            default:        return .center
            }
        }()
        VStack(alignment: alignment, spacing: 8) {
            ForEach(-aboveCount...belowCount, id: \.self) { offset in
                let i = idx + offset
                Group {
                    if lyrics.lines.indices.contains(i) {
                        let text = lyrics.lines[i].text
                        Text(text.isEmpty ? " " : text)
                            .font(offset == 0 ? activeFont : inactiveFont)
                            .foregroundStyle(foreground(for: offset))
                            .scaleEffect(offset == 0 ? 1.0 : 0.92,
                                         anchor: alignment == .leading ? .leading : .center)
                            .multilineTextAlignment(textAlignment)
                            .frame(maxWidth: .infinity, alignment: .init(horizontal: alignment, vertical: .center))
                            .id(i)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                    } else {
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
        if offset == 0 { return activeStyle }
        let fade = max(0.18, 1 - Double(abs(offset)) * 0.28)
        // Layer the inactive style with an opacity multiplier. AnyShapeStyle
        // doesn't expose direct opacity multiplication, so we fall back to a
        // plain Color modifier when the inactive style is nil-equivalent.
        return AnyShapeStyle(inactiveStyle.opacity(fade))
    }
}
