import SwiftUI

extension View {
    /// Like `.frame(width:height:)` but scales the given base dimensions with
    /// the ambient Dynamic Type size, using the `.body` text-style curve.
    func scaledFrame(width: CGFloat? = nil,
                     height: CGFloat? = nil,
                     alignment: Alignment = .center) -> some View {
        modifier(ScaledFrameModifier(baseWidth: width,
                                     baseHeight: height,
                                     alignment: alignment))
    }

    /// Like `.padding(_:)` but scales with Dynamic Type.
    func scaledPadding(_ edges: Edge.Set = .all, _ base: CGFloat) -> some View {
        modifier(ScaledPaddingModifier(edges: edges, base: base))
    }
}

private struct ScaledFrameModifier: ViewModifier {
    let baseWidth: CGFloat?
    let baseHeight: CGFloat?
    let alignment: Alignment
    @ScaledMetric(relativeTo: .body) private var scaleProbe: CGFloat = 100

    func body(content: Content) -> some View {
        let factor = scaleProbe / 100
        content.frame(
            width: baseWidth.map { $0 * factor },
            height: baseHeight.map { $0 * factor },
            alignment: alignment
        )
    }
}

private struct ScaledPaddingModifier: ViewModifier {
    let edges: Edge.Set
    let base: CGFloat
    @ScaledMetric(relativeTo: .body) private var scaleProbe: CGFloat = 100

    func body(content: Content) -> some View {
        content.padding(edges, base * (scaleProbe / 100))
    }
}
