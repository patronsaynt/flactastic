import SwiftUI

struct RiseFadeIn: ViewModifier {
    let delay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .onAppear {
                guard !appeared else { return }
                withAnimation(.easeOut(duration: 0.28).delay(delay)) {
                    appeared = true
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
