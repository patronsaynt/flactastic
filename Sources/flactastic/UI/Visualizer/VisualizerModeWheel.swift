import SwiftUI
import AppKit

/// The hidden left-edge mode wheel. An 18pt hot strip along the leading edge
/// opens a 340pt panel that dims and blurs the canvas behind it, floats a halo
/// and drifting sparkles, and presents every mode as a flat vertical wheel.
/// Scroll, ↑/↓ and click all drive the selection.
///
/// Geometry and timings are ported 1:1 from the design handoff
/// (`design_handoffs/visualizer-revamp`); see `Row.metrics` for the per-row
/// falloff curves.
struct VisualizerModeWheel: View {
    @Binding var mode: VisualizerMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isOpen: Bool = false
    /// Accumulated scroll delta; one mode step per `Self.scrollStep` units.
    @State private var scrollAccumulator: CGFloat = 0
    @State private var scrollMonitor: Any?

    private static let modes = VisualizerMode.allCases
    private static let panelWidth: CGFloat = 340
    private static let hotStripWidth: CGFloat = 18
    private static let rowInset: CGFloat = 56
    /// Scroll travel per mode step. Matches the row pitch, so one notch of the
    /// wheel moves the list by exactly one row.
    private static let scrollStep: CGFloat = Row.pitch

    private var selectedIndex: Int {
        Self.modes.firstIndex(of: mode) ?? 0
    }

    var body: some View {
        // One clock for the sparkles and the selected row's shimmer. Paused
        // while the panel is closed (or Reduce Motion is on) so a hidden wheel
        // costs nothing.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                paused: !isOpen || reduceMotion)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate

            ZStack(alignment: .leading) {
                scrim
                SparkleLayer(now: now, animated: !reduceMotion)
                    .opacity(isOpen ? 0.7 : 0)
                    .allowsHitTesting(false)
                panel(now: now)
                hotStrip
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.42), value: isOpen)
        }
        .background(arrowKeyShortcuts)
        .onChange(of: isOpen) { _, open in
            scrollAccumulator = 0
            open ? installScrollMonitor() : removeScrollMonitor()
        }
        .onDisappear { removeScrollMonitor() }
    }

    // MARK: - Layers

    /// Full-canvas dim + blur behind the panel, matching the design's
    /// `backdrop-filter: blur(26px) brightness(0.55)`.
    ///
    /// The material must be unmasked and unclipped: a `.mask()` or `.clipShape`
    /// pushes it into its own layer, where the backdrop it is supposed to be
    /// sampling is no longer available — it then renders as flat translucency
    /// with no blur at all. So this covers the whole canvas, which is also what
    /// the design specifies. It costs a per-frame backdrop re-sample while the
    /// wheel is open; that is the price of the effect.
    private var scrim: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(VisualizerPalette.scrim)
            .opacity(isOpen ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// The leading strip that wakes the wheel. Deliberately narrow so it never
    /// competes with the visualizer content. Once open it stops hit-testing —
    /// otherwise it would sit on top of the panel's own leading 18pt and steal
    /// the hover, flickering the panel shut.
    private var hotStrip: some View {
        Color.clear
            .frame(width: Self.hotStripWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { isOpen = true }
            }
            .allowsHitTesting(!isOpen)
    }

    private func panel(now: TimeInterval) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: VisualizerPalette.panelWash,
                           startPoint: .leading, endPoint: .trailing)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: VisualizerPalette.panelEdge, location: 0.35),
                    .init(color: VisualizerPalette.panelEdge, location: 0.65),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 1)

            Text("VISUALIZER")
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.5)
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, Self.rowInset)
                .padding(.top, Theme.Spacing.xxl)

            rows(now: now)
        }
        .frame(width: Self.panelWidth)
        .frame(maxHeight: .infinity)
        .clipped()
        .opacity(isOpen ? 1 : 0)
        .offset(x: isOpen ? 0 : -28)
        .allowsHitTesting(isOpen)
        .onHover { hovering in
            isOpen = hovering
        }
    }

    private func rows(now: TimeInterval) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(Self.modes.enumerated()), id: \.element) { index, item in
                let metrics = Row.metrics(distance: index - selectedIndex)
                Row(
                    label: item.wheelLabel,
                    isSelected: item == mode,
                    now: now,
                    // Only the selected row and its immediate neighbours build
                    // the shimmer's GeometryReader + masked gradient. Anything
                    // further out is faded and blurred, and by the time it
                    // could be selected it has already moved into this band.
                    shimmering: !reduceMotion && abs(index - selectedIndex) <= 1
                )
                .frame(height: 34, alignment: .leading)
                .scaleEffect(metrics.scale, anchor: .leading)
                .opacity(metrics.opacity)
                .blur(radius: metrics.blur)
                .offset(x: metrics.x, y: metrics.y)
                .onTapGesture { mode = item }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, Self.rowInset)
        .padding(.trailing, Theme.Spacing.xl)
        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.62), value: selectedIndex)
    }

    // MARK: - Keyboard

    /// ↑/↓ step the wheel while it's open. Mirrors the hidden-shortcut pattern
    /// `VisualizerView` already uses for the queue toggle.
    @ViewBuilder
    private var arrowKeyShortcuts: some View {
        if isOpen {
            ZStack {
                Button("") { step(-1) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("") { step(1) }
                    .keyboardShortcut(.downArrow, modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Scrolling

    /// A local event monitor rather than an `NSView` scroll catcher: the rows
    /// are SwiftUI, so an AppKit sibling never lands in the responder chain
    /// that `scrollWheel` walks. The monitor is installed only while the panel
    /// is open, and swallows the event so the canvas underneath stays put.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            Task { @MainActor in accumulate(event.scrollingDeltaY) }
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    private func accumulate(_ delta: CGFloat) {
        scrollAccumulator += delta
        while abs(scrollAccumulator) >= Self.scrollStep {
            step(scrollAccumulator > 0 ? 1 : -1)
            scrollAccumulator -= (scrollAccumulator < 0 ? -1 : 1) * Self.scrollStep
        }
    }

    /// Clamped, not wrapping — running off either end of the list should feel
    /// like hitting a stop, matching the prototype.
    private func step(_ delta: Int) {
        let next = min(Self.modes.count - 1, max(0, selectedIndex + delta))
        guard next != selectedIndex else { return }
        mode = Self.modes[next]
    }
}

// MARK: - Row

private struct Row: View {
    let label: String
    let isSelected: Bool
    let now: TimeInterval
    let shimmering: Bool

    /// One shimmer sweep, matching `fl-shimmer`'s 3.4s linear loop.
    private static let shimmerPeriod: TimeInterval = 3.4

    /// Every row draws the same face at the same size; selection is expressed
    /// purely through animatable modifiers (scale, colour, shimmer opacity).
    /// Swapping font size or weight between states is what made the label
    /// stutter — SwiftUI can't interpolate those, so it cross-faded the old
    /// and new text on top of each other mid-slide.
    private static let fontSize: CGFloat = 21
    /// 17/21 — the design's unselected size, reached by scaling instead.
    private static let unselectedScale: CGFloat = 17.0 / 21.0

    private var text: Text {
        Text(label)
            .font(.system(size: Self.fontSize, weight: .semibold))
            .tracking(-0.32)
    }

    var body: some View {
        text
            .foregroundStyle(isSelected
                             ? VisualizerPalette.mark
                             : VisualizerPalette.wheelUnselected)
            .fixedSize()
            .overlay { shimmer }
            .shadow(color: VisualizerPalette.mark.opacity(isSelected ? 0.18 : 0),
                    radius: 3)
            .scaleEffect(isSelected ? 1 : Self.unselectedScale, anchor: .leading)
    }

    /// The sweeping highlight on the selected row. Always in the hierarchy and
    /// faded by opacity rather than inserted/removed, so selection changes
    /// cross-fade cleanly instead of popping.
    @ViewBuilder
    private var shimmer: some View {
        if shimmering {
            GeometryReader { geo in
                // CSS: background-size 260%, position sweeping
                // 200% → -60%, i.e. x from -3.2W to +0.96W.
                let width = geo.size.width
                let phase = (now.truncatingRemainder(dividingBy: Self.shimmerPeriod))
                    / Self.shimmerPeriod
                ZStack(alignment: .leading) {
                    LinearGradient(
                        stops: [
                            .init(color: VisualizerPalette.mark, location: 0.18),
                            .init(color: VisualizerPalette.mark, location: 0.38),
                            .init(color: VisualizerPalette.shimmerDip, location: 0.50),
                            .init(color: VisualizerPalette.mark, location: 0.62),
                            .init(color: VisualizerPalette.mark, location: 1.0)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: width * 2.6)
                    .offset(x: -3.2 * width + phase * (4.16 * width))
                }
                .frame(width: width, alignment: .leading)
                .clipped()
            }
            .mask(text)
            .opacity(isSelected ? 1 : 0)
        }
    }

    /// Vertical distance between adjacent rows.
    static let pitch: CGFloat = 46

    /// Per-row falloff, ported verbatim from the prototype's `renderVals()`.
    static func metrics(distance d: Int) -> (x: CGFloat, y: CGFloat, scale: CGFloat, opacity: Double, blur: CGFloat) {
        let ad = abs(d)
        return (
            x: -min(30, CGFloat(ad * ad) * 3),
            y: CGFloat(d) * pitch,
            scale: max(0.74, 1 - CGFloat(ad) * 0.055),
            opacity: max(0.1, 1 - Double(ad) * 0.19),
            blur: min(2.4, CGFloat(ad) * 0.45)
        )
    }
}

// MARK: - Sparkles

/// The halo and drifting motes that float behind the open wheel. Drawn in a
/// single `Canvas` — 20 individually-animated views would be 20 layers of
/// SwiftUI bookkeeping for what is a handful of circles.
private struct SparkleLayer: View {
    let now: TimeInterval
    let animated: Bool

    /// `SPARKS` from the prototype, verbatim: position in percent of the
    /// canvas, dot size, glow radius, cycle duration and start delay.
    private static let sparks: [Spark] = [
        .init(left: 3,  top: 68, size: 2.5, glow: 9,  duration: 6.2, delay: 0.0),
        .init(left: 9,  top: 82, size: 1.5, glow: 6,  duration: 7.8, delay: 0.9),
        .init(left: 16, top: 58, size: 2.0, glow: 8,  duration: 5.6, delay: 1.7),
        .init(left: 24, top: 74, size: 1.5, glow: 5,  duration: 8.4, delay: 0.4),
        .init(left: 32, top: 44, size: 1.8, glow: 7,  duration: 6.9, delay: 2.6),
        .init(left: 40, top: 80, size: 2.2, glow: 9,  duration: 7.2, delay: 1.2),
        .init(left: 48, top: 30, size: 1.4, glow: 5,  duration: 9.1, delay: 3.4),
        .init(left: 55, top: 88, size: 2.6, glow: 11, duration: 5.9, delay: 2.1),
        .init(left: 63, top: 62, size: 1.6, glow: 6,  duration: 8.8, delay: 0.6),
        .init(left: 71, top: 22, size: 2.0, glow: 8,  duration: 7.4, delay: 4.2),
        .init(left: 78, top: 52, size: 1.5, glow: 5,  duration: 6.6, delay: 3.0),
        .init(left: 85, top: 18, size: 1.8, glow: 7,  duration: 9.6, delay: 1.5),
        .init(left: 91, top: 46, size: 1.4, glow: 5,  duration: 8.2, delay: 2.9),
        .init(left: 12, top: 92, size: 2.3, glow: 10, duration: 6.4, delay: 3.8),
        .init(left: 60, top: 12, size: 1.6, glow: 6,  duration: 7.0, delay: 1.9),
        .init(left: 95, top: 76, size: 1.9, glow: 8,  duration: 8.6, delay: 0.2),
        .init(left: 5,  top: 20, size: 1.4, glow: 5,  duration: 9.3, delay: 2.4),
        .init(left: 68, top: 66, size: 2.1, glow: 9,  duration: 6.0, delay: 3.1),
        .init(left: 44, top: 55, size: 1.5, glow: 6,  duration: 7.6, delay: 1.0),
        .init(left: 27, top: 10, size: 1.7, glow: 7,  duration: 8.9, delay: 4.5)
    ]

    struct Spark {
        let left: Double, top: Double
        let size: CGFloat, glow: CGFloat
        let duration: Double, delay: Double
    }

    var body: some View {
        Canvas { ctx, size in
            drawHalo(ctx: &ctx, size: size)
            for spark in Self.sparks {
                draw(spark, ctx: &ctx, size: size)
            }
        }
    }

    /// `fl-halo`: 4.6s ease-in-out, opacity 0.42 ↔ 0.85, scale 1 ↔ 1.14.
    private func drawHalo(ctx: inout GraphicsContext, size: CGSize) {
        let phase = animated ? easeInOut(pingPong(now / 4.6)) : 0.5
        let opacity = 0.42 + (0.85 - 0.42) * phase
        let scale = 1 + 0.14 * phase
        let diameter = 420 * scale
        let center = CGPoint(x: size.width * 0.06, y: size.height * 0.5)
        let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                          width: diameter, height: diameter)
        ctx.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [
                    VisualizerPalette.mark.opacity(0.14 * opacity / 0.85),
                    VisualizerPalette.mark.opacity(0)
                ]),
                center: center, startRadius: 0, endRadius: diameter * 0.34
            )
        )
    }

    /// `fl-drift`: a linear rise of (26, −120) with a 0.6 → 1.1 scale-up, and
    /// an opacity envelope of 0 → 1 (18%) → 0.7 (70%) → 0.
    private func draw(_ spark: Spark, ctx: inout GraphicsContext, size: CGSize) {
        let t: Double = animated
            ? ((now + spark.delay).truncatingRemainder(dividingBy: spark.duration)) / spark.duration
            : 0.4
        let opacity: Double
        switch t {
        case ..<0.18:  opacity = t / 0.18
        case ..<0.70:  opacity = 1 - (t - 0.18) / 0.52 * 0.3
        default:       opacity = 0.7 * (1 - (t - 0.70) / 0.30)
        }
        guard opacity > 0.01 else { return }

        let scale = 0.6 + 0.5 * t
        let x = size.width * spark.left / 100 + 26 * t
        let y = size.height * spark.top / 100 - 120 * t
        let radius = spark.size / 2 * scale

        // Bloom first, then the hard dot on top — the Canvas equivalent of the
        // prototype's `box-shadow` glow.
        let glowRect = CGRect(x: x - spark.glow, y: y - spark.glow,
                              width: spark.glow * 2, height: spark.glow * 2)
        ctx.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [
                    VisualizerPalette.mark.opacity(0.55 * opacity),
                    VisualizerPalette.mark.opacity(0)
                ]),
                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: spark.glow
            )
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                   width: radius * 2, height: radius * 2)),
            with: .color(VisualizerPalette.mark.opacity(opacity))
        )
    }

    /// 0 → 1 → 0 over one cycle, for the CSS `0%, 100% … 50%` keyframe shape.
    private func pingPong(_ v: Double) -> Double {
        let f = v.truncatingRemainder(dividingBy: 1)
        return f < 0.5 ? f * 2 : (1 - f) * 2
    }

    private func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
}
