import SwiftUI
import AppKit

@main
struct FlactasticApp: App {
    @State private var library = LibraryStore()
    @State private var player = PlayerState()
    @State private var settings = Settings()
    @State private var playlistStore = PlaylistStore()
    @State private var metadataWriter = MetadataWriter()
    @State private var importCoordinator = ImportCoordinator()
    @State private var router = NavigationRouter()

    var body: some Scene {
        WindowGroup {
            GeometryReader { geo in
                ContentView()
                    .environment(library)
                    .environment(player)
                    .environment(settings)
                    .environment(playlistStore)
                    .environment(importCoordinator)
                    .environment(router)
                    .environment(\.metadataWriter, metadataWriter)
                    .frame(
                        width: max(1, geo.size.width / settings.uiScale),
                        height: max(1, geo.size.height / settings.uiScale)
                    )
                    .scaleEffect(settings.uiScale, anchor: .topLeading)
            }
            .preferredColorScheme(settings.useLightMode ? .light : .dark)
            .frame(minWidth: 1000, minHeight: 650)
            .background(Theme.background)
            .task { await bootstrap() }
            .onAppear {
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSWindow.allowsAutomaticWindowTabbing = false
                installSpacebarMonitor()
            }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Collection") {
                Button("Refresh Collection") { library.refreshLibrary() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Import Track…") { importCoordinator.begin(.track) }
                Button("Import Album…") { importCoordinator.begin(.album) }
                Button("Import Files as Playlist…") { importCoordinator.begin(.playlist) }
            }
            CommandMenu("Playback") {
                Button("Play / Pause") { player.engine.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Next") { player.next() }
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

        // Menu bar mini-player. The `isInserted` binding reflects the Settings
        // toggle live (Settings is @Observable), so flipping the option in
        // Settings adds/removes the menu bar icon without needing a restart.
        MenuBarExtra(isInserted: menuBarBinding) {
            MenuBarPlayerView()
                .environment(library)
                .environment(player)
                .environment(settings)
                .environment(playlistStore)
        } label: {
            Image(systemName: "music.note")
        }
        .menuBarExtraStyle(.window)
    }

    /// A `Binding<Bool>` over `settings.showMenuBarPlayer` for `MenuBarExtra`'s
    /// `isInserted` parameter. Built inline so we don't need `@Bindable` here.
    private var menuBarBinding: Binding<Bool> {
        Binding(
            get: { settings.showMenuBarPlayer && player.isPlaying },
            set: { _ in }
        )
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
                return
            }
        }
        // Nothing to scan — reveal the UI immediately so the empty state shows.
        withAnimation(.easeOut(duration: 0.35)) {
            library.hasCompletedInitialLoad = true
        }
    }
}
