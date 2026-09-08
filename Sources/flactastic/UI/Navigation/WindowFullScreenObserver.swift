import SwiftUI
import AppKit

/// Bridges `NSWindow` fullscreen notifications into a SwiftUI binding so the
/// app can hide its custom top bar when the user enters fullscreen mode.
///
/// Observer tokens are owned by a `Coordinator` so they're attached exactly
/// once per window and properly removed on teardown — without this, every
/// SwiftUI re-render would stack new closure observers, which caused stale
/// duplicates to fire after exiting fullscreen and leave the window stuck.
struct WindowFullScreenObserver: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isFullScreen: $isFullScreen)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        @Binding private var isFullScreen: Bool
        private weak var observedWindow: NSWindow?
        private var enterToken: NSObjectProtocol?
        private var exitToken: NSObjectProtocol?

        init(isFullScreen: Binding<Bool>) {
            self._isFullScreen = isFullScreen
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            // Already wired to this window — just sync state and return.
            if observedWindow === window {
                syncState(from: window)
                return
            }
            detach()
            observedWindow = window
            syncState(from: window)
            let center = NotificationCenter.default
            enterToken = center.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.isFullScreen = true }
            }
            exitToken = center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.isFullScreen = false }
            }
        }

        func detach() {
            let center = NotificationCenter.default
            if let enterToken { center.removeObserver(enterToken) }
            if let exitToken { center.removeObserver(exitToken) }
            enterToken = nil
            exitToken = nil
            observedWindow = nil
        }

        private func syncState(from window: NSWindow) {
            let fs = window.styleMask.contains(.fullScreen)
            if fs != isFullScreen { isFullScreen = fs }
        }
    }
}
