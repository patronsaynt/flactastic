import SwiftUI

struct RiseFadeIn: ViewModifier {
    @Environment(Settings.self) private var settings
    let delay: Double
    @State private var appeared = false

    private var offsetX: CGFloat {
        guard !appeared else { return 0 }
        switch settings.fadeAnimationDirection {
        case .up: return 0
        case .leftToRight: return -10
        case .rightToLeft: return 10
        }
    }

    private var offsetY: CGFloat {
        guard !appeared else { return 0 }
        switch settings.fadeAnimationDirection {
        case .up: return 10
        case .leftToRight, .rightToLeft: return 0
        }
    }

    func body(content: Content) -> some View {
        if !settings.fadeAnimationsEnabled {
            content
        } else {
            content
                .opacity(appeared ? 1 : 0)
                .offset(x: offsetX, y: offsetY)
                .onAppear {
                    guard !appeared else { return }
                    withAnimation(.easeOut(duration: 0.28).delay(delay)) {
                        appeared = true
                    }
                }
        }
    }
}

extension View {
    func riseFadeIn(delay: Double = 0) -> some View {
        modifier(RiseFadeIn(delay: delay))
    }

    func riseFadeIn(index: Int, step: Double = 0.015, max: Double = 0.25) -> some View {
        modifier(RiseFadeIn(delay: Swift.min(Double(index) * step, max)))
    }
}
