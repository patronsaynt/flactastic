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

        private let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        /// Each button's stock origin within its superview (`NSTitlebarView`),
        /// captured once. This is a fixed OS constant — confirmed by logging
        /// it across launch-time window-frame restoration and manual resizes,
        /// it never moves — so the target position can always be recomputed
        /// from it directly, without ever reading the button's current (and
        /// possibly already-nudged) frame as if it were a fresh baseline.
        /// That keeps every reposition idempotent no matter what triggers it.
        private var stockOrigins: [NSWindow.ButtonType: CGPoint] = [:]

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            configure(window)
            captureStockOrigins(in: window)

            // Re-assert the custom title bar after exiting native fullscreen
            // (Big Picture mode). Fullscreen resets the style mask, which would
            // otherwise restore a real title bar and leave the content offset
            // so clicks miss their targets.
            NotificationCenter.default.addObserver(
                self, selector: #selector(didExitFullScreen),
                name: NSWindow.didExitFullScreenNotification, object: window
            )

            // AppKit re-lays out the standard window buttons on its own schedule
            // — window-frame restoration at launch, live resize, fullscreen
            // transitions — and any of those passes can move them. A one-shot
            // nudge therefore survives only if nothing else lays out afterwards,
            // which is exactly why the offsets held when running unbundled but
            // were lost in the packaged app (a bundled launch restores the saved
            // window frame after the content view is installed). Observing each
            // button's frame means every relayout is corrected, whoever caused
            // it — and since `reposition` recomputes the target from the fixed
            // stock origin rather than the button's own (possibly already-
            // nudged) frame, reacting to our own writes can't compound the
            // offset.
            observeButtonFrames(in: window)
            repositionTrafficLights()
            DispatchQueue.main.async { [weak self] in self?.repositionTrafficLights() }
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        private func configure(_ window: NSWindow) {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }

        private func captureStockOrigins(in window: NSWindow) {
            guard stockOrigins.isEmpty else { return }
            for type in buttonTypes {
                guard let button = window.standardWindowButton(type) else { continue }
                stockOrigins[type] = button.frame.origin
            }
        }

        @objc private func didExitFullScreen() {
            guard let window else { return }
            configure(window)
            DispatchQueue.main.async { [weak self] in self?.repositionTrafficLights() }
        }

        private func observeButtonFrames(in window: NSWindow) {
            for type in buttonTypes {
                guard let button = window.standardWindowButton(type) else { continue }
                button.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self, selector: #selector(buttonFrameChanged(_:)),
                    name: NSView.frameDidChangeNotification, object: button
                )
            }
        }

        @objc private func buttonFrameChanged(_ note: Notification) {
            guard let button = note.object as? NSView,
                  let type = buttonTypes.first(where: { window?.standardWindowButton($0) === button })
            else { return }
            reposition(type, button: button)
        }

        @objc private func repositionTrafficLights() {
            guard let window else { return }
            for type in buttonTypes {
                guard let button = window.standardWindowButton(type) else { continue }
                reposition(type, button: button)
            }
        }

        private func reposition(_ type: NSWindow.ButtonType, button: NSView) {
            // In native fullscreen the system owns the buttons — leave them be.
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            guard let stock = stockOrigins[type] else { return }
            let target = CGPoint(x: stock.x + dx, y: stock.y + dy)
            // Already sitting where it belongs — nothing to do. This is also
            // what stops the notification we trigger below from recursing.
            guard button.frame.origin != target else { return }
            button.setFrameOrigin(target)
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
