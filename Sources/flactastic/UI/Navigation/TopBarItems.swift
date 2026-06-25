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
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
        }
    }
}

/// Reaches into the hosting `NSWindow` and configures it for a full-size,
/// transparent title bar so app content (the custom top bar) draws edge-to-edge
/// up into the title-bar region and shares the row with the traffic lights.
struct TitleBarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
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
