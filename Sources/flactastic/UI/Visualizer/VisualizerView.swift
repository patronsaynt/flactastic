import SwiftUI
import AppKit

struct VisualizerView: View {
    @Environment(PlayerState.self) private var player
    @Environment(Settings.self)    private var settings

    @State private var analyzer = SpectrumAnalyzer()
    @State private var isFullScreen: Bool = false

    /// Height of the hover-reveal zone at the top of the canvas. Only this
    /// strip activates the picker — the rest of the visualizer area is
    /// uninterrupted.
    private let hoverZoneHeight: CGFloat = 64

    var body: some View {
        @Bindable var settings = settings
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            content(for: settings.visualizerMode)
                .id(settings.visualizerMode)
                .transition(.opacity)

            VisualizerModePicker(mode: $settings.visualizerMode)
                .frame(height: hoverZoneHeight)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.sm)
                .allowsHitTesting(true)

            // Hidden affordance: pressing Q toggles the queue panel while
            // the visualizer is on screen.
            Button("") { player.isQueueVisible.toggle() }
                .keyboardShortcut("q", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            // Fullscreen toggle — only shown in Big Picture mode, sits
            // unobtrusively in the top-right corner. Can be hidden via
            // Settings → Visualizer.
            if settings.visualizerMode == .bigPicture && settings.showBigPictureFullScreenToggle {
                fullScreenToggle
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topTrailing)
                    .padding(Theme.Spacing.lg)
                    .allowsHitTesting(true)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: settings.visualizerMode)
        .onAppear {
            syncTap(for: settings.visualizerMode)
            if settings.visualizerMode == .bigPicture {
                requestFullScreen()
            }
        }
        .onDisappear { analyzer.detach() }
        .onChange(of: settings.visualizerMode) { _, newMode in
            syncTap(for: newMode)
            if newMode == .bigPicture {
                requestFullScreen()
            }
        }
        .background(WindowFullScreenObserver(isFullScreen: $isFullScreen))
        .toolbar(isFullScreen ? .hidden : .automatic, for: .windowToolbar)
    }

    @ViewBuilder
    private func content(for mode: VisualizerMode) -> some View {
        switch mode {
        case .albumArtLarge, .albumArtLargeDetails,
             .albumArtSmallDetails,
             .albumArtWheel:
            AlbumArtVisualizerView(mode: mode)
        case .lyrics:
            LyricsVisualizerView()
        case .spectrumRadial, .spectrumHorizontal, .spectrogram:
            SpectrumVisualizerView(mode: mode, analyzer: analyzer)
        case .bigPicture:
            BigPictureVisualizerView()
        }
    }

    private func requestFullScreen() {
        guard !isFullScreen else { return }
        // Defer until after the view is in the window hierarchy.
        DispatchQueue.main.async {
            NSApp.keyWindow?.toggleFullScreen(nil)
        }
    }

    private var fullScreenToggle: some View {
        Button {
            NSApp.keyWindow?.toggleFullScreen(nil)
        } label: {
            Image(systemName: isFullScreen
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                .contentShape(Rectangle())
                .padding(6)
        }
        .buttonStyle(.plain)
        .help(isFullScreen ? "Exit Full Screen" : "Enter Full Screen")
    }

    private func syncTap(for mode: VisualizerMode) {
        if mode.requiresAudioTap {
            analyzer.attach(to: player.engine)
        } else {
            analyzer.detach()
        }
    }
}

/// Bridges `NSWindow` fullscreen notifications into a SwiftUI binding so
/// the visualizer can hide the toolbar when the user enters fullscreen mode.
///
/// Observer tokens are owned by a `Coordinator` so they're attached exactly
/// once per window and properly removed on teardown — without this, every
/// SwiftUI re-render would stack new closure observers, which caused stale
/// duplicates to fire after exiting fullscreen and leave the window stuck.
private struct WindowFullScreenObserver: NSViewRepresentable {
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
