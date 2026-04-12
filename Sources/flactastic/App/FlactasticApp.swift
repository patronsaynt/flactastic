import SwiftUI
import AppKit

@main
struct FlactasticApp: App {
    @State private var library = LibraryStore()
    @State private var player = PlayerState()
    @State private var settings = Settings()
    @State private var playlistStore = PlaylistStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(player)
                .environment(settings)
                .environment(playlistStore)
                .preferredColorScheme(settings.useLightMode ? .light : .dark)
                .frame(minWidth: 1000, minHeight: 650)
                .background(Theme.background)
                .task { await bootstrap() }
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    installSpacebarMonitor()
                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Playback") {
                Button("Play / Pause") { player.engine.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Next") { player.engine.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous") { player.engine.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button("Volume Up") { player.engine.volumeUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Volume Down") { player.engine.volumeDown() }
                    .keyboardShortcut(.downArrow, modifiers: .command)
            }
        }
    }

    /// Intercept the spacebar at the app level so it always triggers play/pause,
    /// even when a text field or other control has keyboard focus.
    private func installSpacebarMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [player] event in
            // Only bare space (no modifiers except shift which would be the same key)
            guard event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                      .subtracting(.capsLock) == [] else {
                return event
            }
            // Don't swallow space when a text field is editing
            if let responder = event.window?.firstResponder,
               responder is NSTextView {
                return event
            }
            player.engine.togglePlayPause()
            return nil // consume the event
        }
    }

    @MainActor
    private func bootstrap() async {
        playlistStore.load()
        player.engine.setVolume(settings.volume)
        if let path = settings.lastRootPath {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                library.openFolder(url)
            }
        }
    }
}
