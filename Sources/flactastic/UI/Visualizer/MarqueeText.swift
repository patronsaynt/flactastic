import SwiftUI

/// Single-line text that, when wider than its container, smoothly slides
/// back and forth instead of wrapping. When the text fits, it renders
/// statically with no animation overhead.
///
/// Layout strategy: a transparent, single-line truncated copy of the text
/// acts as a sizing anchor — it takes whatever width the parent offers and
/// reports the correct height. The visible copy is overlaid on top with
/// `.fixedSize(horizontal: true)` so it has its natural width, but the
/// overlay does not influence the parent's size, so it can be clipped
/// reliably regardless of how much the title overflows.
struct MarqueeText: View {
    let text: String
    var font: Font = Theme.Font.body
    var weight: Font.Weight? = nil
    var foregroundStyle: AnyShapeStyle = AnyShapeStyle(Theme.textPrimary)
    /// Resting alignment used when the text fits its container. When the
    /// text overflows the container, scrolling always starts from the
    /// leading edge regardless of this value.
    var alignment: HorizontalAlignment = .leading
    /// Scrolling speed in points per second.
    var speed: Double = 30
    /// Pause at each end of the cycle, in seconds.
    var pause: Double = 1.0

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animationToken: Int = 0

    var body: some View {
        let styledFont: Font = weight.map { font.weight($0) } ?? font
        // Once we know the text overflows, pin to leading so the scroll
        // animation starts from the natural read position. Until then,
        // honour the caller's alignment.
        let isOverflowing = textWidth > containerWidth + 0.5 && containerWidth > 0
        let effectiveAlignment: HorizontalAlignment = isOverflowing ? .leading : alignment
        let frameAlignment: Alignment = .init(horizontal: effectiveAlignment, vertical: .center)

        return Text(text)
            // Hidden sizing anchor: takes the parent's offered width and
            // contributes the correct line height. Truncation keeps it
            // single-line so the parent doesn't grow vertically either.
            .font(styledFont)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.clear)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: ContainerWidthKey.self, value: g.size.width)
                }
            )
            .overlay(alignment: frameAlignment) {
                Text(text)
                    .font(styledFont)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(foregroundStyle)
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: TextWidthKey.self, value: g.size.width)
                        }
                    )
                    .offset(x: offset)
            }
            .clipShape(Rectangle())
            .onPreferenceChange(TextWidthKey.self) { w in
                if abs(textWidth - w) > 0.5 {
                    textWidth = w
                    restart()
                }
            }
            .onPreferenceChange(ContainerWidthKey.self) { w in
                if abs(containerWidth - w) > 0.5 {
                    containerWidth = w
                    restart()
                }
            }
            .onChange(of: text) { _, _ in restart() }
    }

    private func restart() {
        guard textWidth > 0, containerWidth > 0 else { return }

        animationToken &+= 1
        let token = animationToken

        var resetTx = Transaction()
        resetTx.disablesAnimations = true
        withTransaction(resetTx) {
            offset = 0
        }

        guard textWidth > containerWidth + 0.5 else { return }

        let distance = textWidth - containerWidth + 16
        let scrollDuration = max(0.5, Double(distance) / speed)

        DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
            guard token == animationToken else { return }
            withAnimation(.linear(duration: scrollDuration)) {
                offset = -distance
            }
            scheduleReturn(token: token,
                           distance: distance,
                           scrollDuration: scrollDuration)
        }
    }

    private func scheduleReturn(token: Int, distance: CGFloat, scrollDuration: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + scrollDuration + pause) {
            guard token == animationToken else { return }
            withAnimation(.linear(duration: scrollDuration)) {
                offset = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + scrollDuration + pause) {
                guard token == animationToken else { return }
                withAnimation(.linear(duration: scrollDuration)) {
                    offset = -distance
                }
                scheduleReturn(token: token,
                               distance: distance,
                               scrollDuration: scrollDuration)
            }
        }
    }
}

private struct TextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContainerWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
