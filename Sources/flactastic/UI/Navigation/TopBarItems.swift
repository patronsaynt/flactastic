import SwiftUI
import AppKit

/// Custom window top bar that sits in the same row as the macOS traffic lights
/// (the window uses a hidden title bar). Hosting the tab bar here instead of in
/// the system toolbar gives full control over height, so the pill container is
/// no longer clipped by the toolbar's fixed item height.
struct TopBarView: View {
    @Binding var selectedTab: AppTab
    var onSettings: () -> Void

    var body: some View {
        ZStack {
            // Centred tab group. The traffic lights occupy the far left and the
            // centred group clears them, matching the old principal placement.
            TabBarView(selectedTab: $selectedTab)

            HStack {
                Spacer()
                SettingsBarButton(action: onSettings)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .padding(.horizontal, 16)
        .background(WindowDragArea())     // empty areas drag the window
        .background(Theme.background)
    }
}

/// Reaches into the hosting `NSWindow` and configures it for a full-size,
/// transparent title bar so app content (the custom top bar) draws edge-to-edge
/// up into the title-bar region and shares the row with the traffic lights.
/// Also nudges the traffic lights inward and down so they line up vertically
/// with the pills in the custom top bar.
struct TitleBarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfiguratorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguratorView: NSView {
        /// Offsets applied to the standard window buttons. Tweak to taste:
        /// `dx` moves the group inward (right); `dy` moves it down (AppKit's
        /// y-axis points up, so a negative value moves the lights downward).
        private let dx: CGFloat = 8
        private let dy: CGFloat = -11

        /// Default origins captured once, so reapplying never compounds.
        private var defaults: [NSWindow.ButtonType: CGPoint] = [:]

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            configure(window)

            // Re-assert the custom title bar after exiting native fullscreen
            // (Big Picture mode). Fullscreen resets the style mask, which would
            // otherwise restore a real title bar and leave the content offset
            // so clicks miss their targets.
            NotificationCenter.default.addObserver(
                self, selector: #selector(didExitFullScreen),
                name: NSWindow.didExitFullScreenNotification, object: window
            )
            DispatchQueue.main.async { [weak self] in self?.repositionTrafficLights() }
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        private func configure(_ window: NSWindow) {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }

        @objc private func didExitFullScreen() {
            guard let window else { return }
            configure(window)
            DispatchQueue.main.async { [weak self] in self?.repositionTrafficLights() }
        }

        @objc private func repositionTrafficLights() {
            // In native fullscreen the system owns the buttons — leave them be.
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(type) else { continue }
                if defaults[type] == nil { defaults[type] = button.frame.origin }
                guard let base = defaults[type] else { continue }
                button.setFrameOrigin(CGPoint(x: base.x + dx, y: base.y + dy))
            }
        }
    }
}

/// Transparent NSView that lets click-drags in empty top-bar space move the
/// window — restores the drag behaviour normally provided by the title bar.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

/// Circular back control for detail views. Navigation is driven manually via
/// `NavigationRouter` paths (no `NavigationStack`) because on macOS a
/// `NavigationStack` routes its back button through the window toolbar, which
/// can't coexist with the custom top bar.
struct DetailBackButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.surface))
        }
        .buttonStyle(BarPressButtonStyle())
    }
}

/// Settings entry point, styled to mirror a resting tab from `TabBarView` —
/// a surface-filled pill with an icon + label.
struct SettingsBarButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .regular))
                Text("Settings")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.surface)
            }
        }
        .buttonStyle(BarPressButtonStyle())
    }
}

/// Press feedback (scale + fade) matching the tab buttons in `TabBarView`.
struct BarPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.65),
                value: configuration.isPressed
            )
    }
}
