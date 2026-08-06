import SwiftUI
import AppKit

struct VisualizerView: View {
    @Environment(PlayerState.self) private var player
    @Environment(Settings.self)    private var settings

    @State private var analyzer = SpectrumAnalyzer()
    @State private var isFullScreen: Bool = false

    /// The window hosting this view, captured by `WindowFullScreenObserver`.
    /// Fullscreen toggles and toolbar restoration MUST target this window,
    /// not `NSApp.keyWindow` — during fullscreen transitions (including the
    /// system's own Esc exit) there is briefly no key window, so a
    /// keyWindow-based restore silently no-ops and leaves the windowed view
    /// with its toolbar missing.
    @State private var hostWindow: NSWindow?

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
        .onDisappear {
            analyzer.detach()
            // Restore the toolbar if the user leaves the visualizer while
            // still in fullscreen.
            applyToolbarVisibility(fullScreen: false)
        }
        .onChange(of: settings.visualizerMode) { oldMode, newMode in
            syncTap(for: newMode)
            if newMode == .bigPicture {
                requestFullScreen()
            } else if oldMode == .bigPicture {
                // Jumping out of Big Picture via the mode picker: return to
                // the windowed view instead of stranding the user fullscreen
                // in another visualizer. (When this change was itself caused
                // by an Esc fullscreen exit, the window is already windowed
                // and the styleMask guard makes this a no-op.)
                requestExitFullScreen()
            }
        }
        .background(WindowFullScreenObserver(isFullScreen: $isFullScreen, window: $hostWindow))
        .onChange(of: isFullScreen) { _, fs in
            // Drive toolbar visibility imperatively rather than via SwiftUI's
            // `.toolbar(.hidden, for: .windowToolbar)`. The parent ContentView
            // owns the toolbar items, so a child-level visibility modifier
            // didn't reliably hide them — and toggling it during the
            // fullscreen animation could deadlock the window on exit.
            applyToolbarVisibility(fullScreen: fs)

            // Big Picture only makes sense fullscreen. When the user exits
            // fullscreen, drop back to the small-details visualizer so they
            // aren't stranded in Big Picture with no obvious way out.
            if !fs && settings.visualizerMode == .bigPicture {
                settings.visualizerMode = .albumArtSmallDetails
            }
        }
    }

    private func applyToolbarVisibility(fullScreen: Bool) {
        let window = hostWindow
        DispatchQueue.main.async {
            guard let toolbar = (window ?? NSApp.keyWindow)?.toolbar else { return }
            let shouldShow = !fullScreen
            if toolbar.isVisible != shouldShow {
                toolbar.isVisible = shouldShow
            }
        }
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
        // Defer until after the view is in the window hierarchy, and check
        // the window's REAL state inside the deferred block: the SwiftUI
        // `isFullScreen` mirror can lag during transitions, and a stale guard
        // here turns "enter fullscreen" into a toggle *out* of it.
        let window = hostWindow
        DispatchQueue.main.async {
            guard let window = window ?? NSApp.keyWindow,
                  !window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
        }
    }

    private func requestExitFullScreen() {
        let window = hostWindow
        DispatchQueue.main.async {
            guard let window = window ?? NSApp.keyWindow,
                  window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
        }
    }

    private var fullScreenToggle: some View {
        Button {
            (hostWindow ?? NSApp.keyWindow)?.toggleFullScreen(nil)
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
    /// The concrete window this view lives in, published so the visualizer
    /// can target it directly instead of `NSApp.keyWindow` (which is nil
    /// mid-fullscreen-transition).
    @Binding var window: NSWindow?

    func makeCoordinator() -> Coordinator {
        Coordinator(isFullScreen: $isFullScreen, window: $window)
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
        @Binding private var hostWindow: NSWindow?
        private weak var observedWindow: NSWindow?
        private var enterToken: NSObjectProtocol?
        private var exitToken: NSObjectProtocol?

        init(isFullScreen: Binding<Bool>, window: Binding<NSWindow?>) {
            self._isFullScreen = isFullScreen
            self._hostWindow = window
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
            if hostWindow !== window { hostWindow = window }
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
