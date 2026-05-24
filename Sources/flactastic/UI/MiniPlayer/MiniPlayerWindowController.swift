import SwiftUI
import AppKit

/// Bridges the `MiniPlayerPresenter.isVisible` flag to the SwiftUI
/// `Window(id: "mini-player")` scene.
///
/// **Open path** — flag flips to `true`: open the window scene, then
/// minimize the main window so the user's focus shifts.
///
/// **Close path** — handled via a single `NSWindow.willCloseNotification`
/// observer (not SwiftUI's `.onDisappear`, which is unreliable for
/// programmatically-dismissed Window scenes). Whichever way the mini player
/// closes (red traffic light, ⌘W, the expand-button → `dismissWindow`),
/// the observer restores the main window and resyncs `presenter.isVisible`.
struct MiniPlayerWindowController: View {
    @Environment(MiniPlayerPresenter.self) private var presenter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var closeObserver: NSObjectProtocol?

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { installCloseObserverIfNeeded() }
            .onChange(of: presenter.isVisible) { _, visible in
                if visible {
                    openWindow(id: "mini-player")
                    minimizeMainWindow()
                } else {
                    // Triggers the willCloseNotification observer, which
                    // handles main-window restore for ALL close paths.
                    dismissWindow(id: "mini-player")
                }
            }
    }

    // MARK: - Observer

    private func installCloseObserverIfNeeded() {
        guard closeObserver == nil else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier?.rawValue == "mini-player" else { return }
            // Restore the main window and resync presenter. Done on a Task
            // hop so we leave the willClose delegate cleanly.
            Task { @MainActor in
                restoreMainWindow()
                if presenter.isVisible { presenter.isVisible = false }
            }
        }
    }

    // MARK: - Window juggling

    private func minimizeMainWindow() {
        DispatchQueue.main.async {
            for window in NSApp.windows
            where window.identifier?.rawValue != "mini-player"
                && window.canBecomeMain
                && window.isVisible {
                window.miniaturize(nil)
            }
        }
    }

    @MainActor
    private func restoreMainWindow() {
        for window in NSApp.windows
        where window.identifier?.rawValue != "mini-player" && window.canBecomeMain {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
