import SwiftUI
import AppKit

@main
struct FlactasticApp: App {
    @State private var library = LibraryStore()
    @State private var player = PlayerState()
    @State private var settings = Settings()
    @State private var playlistStore = PlaylistStore()
    @State private var artistStore: ArtistStore
    @State private var artistRemoteCache: ArtistRemoteCache
    @State private var artistImageFetcher: ArtistImageFetcher
    @State private var lyricsRemoteCache: LyricsRemoteCache
    @State private var lyricsFetcher: LyricsFetcher

    init() {
        let store = ArtistStore()
        let cache = ArtistRemoteCache()
        _artistStore = State(initialValue: store)
        _artistRemoteCache = State(initialValue: cache)
        _artistImageFetcher = State(initialValue: ArtistImageFetcher(cache: cache, store: store))

        // Streaming downloads: a single Lucida provider backed by a hidden
        // WKWebView pointed at lucida.to. The WebView clears Cloudflare in
        // the background so the first paste-and-resolve is fast.
        let registry = StreamerRegistry()
        let lucidaController = LucidaWebController()
        registry.register(LucidaWebProvider(controller: lucidaController))
        _lucidaController = State(initialValue: lucidaController)
        let lib = LibraryStore()
        let writer = MetadataWriter()
        _streamerRegistry = State(initialValue: registry)
        _downloadCoordinator = State(initialValue: DownloadCoordinator(
            registry: registry, library: lib, writer: writer
        ))
        // Reuse the same library/writer instances above.
        _library = State(initialValue: lib)
        _metadataWriter = State(initialValue: writer)

        let lyricsCache = LyricsRemoteCache()
        _lyricsRemoteCache = State(initialValue: lyricsCache)
        _lyricsFetcher = State(initialValue: LyricsFetcher(
            cache: lyricsCache,
            metadataWriter: writer
        ))
    }
    @State private var metadataWriter = MetadataWriter()
    @State private var importCoordinator = ImportCoordinator()
    @State private var playlistAddCoordinator = PlaylistAddCoordinator()
    @State private var router = NavigationRouter()
    @State private var discordPresence = DiscordPresenceService()
    @State private var streamerRegistry = StreamerRegistry()
    @State private var downloadCoordinator: DownloadCoordinator
    @State private var lucidaController: LucidaWebController
    /// In-memory only — the Lucida debug window is a developer tool and
    /// always starts OFF on launch, even if the user left it enabled in
    /// the previous session.
    @State private var lucidaDebugEnabled = false

    var body: some Scene {
        WindowGroup {
            GeometryReader { geo in
                Group {
                    if settings.hasCompletedOnboarding {
                        ContentView()
                            .environment(library)
                            .environment(player)
                            .environment(settings)
                            .environment(playlistStore)
                            .environment(artistStore)
                            .environment(artistRemoteCache)
                            .environment(artistImageFetcher)
                            .environment(lyricsRemoteCache)
                            .environment(lyricsFetcher)
                            .environment(importCoordinator)
                            .environment(playlistAddCoordinator)
                            .environment(router)
                            .environment(streamerRegistry)
                            .environment(downloadCoordinator)
                            .environment(lucidaController)
                            .environment(\.debugMode, lucidaDebugEnabled)
                            .environment(\.metadataWriter, metadataWriter)
                            .transition(.opacity)
                    } else {
                        OnboardingView()
                            .environment(library)
                            .environment(settings)
                            .transition(.opacity)
                    }
                }
                .frame(
                    width: max(1, geo.size.width / settings.uiScale),
                    height: max(1, geo.size.height / settings.uiScale)
                )
                .scaleEffect(settings.uiScale, anchor: .topLeading)
            }
            .sheet(isPresented: Binding(
                get: { lucidaController.needsUserChallenge },
                set: { _ in }
            )) {
                LucidaChallengeSheet()
                    .environment(lucidaController)
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
                applyAppearance(useLight: settings.useLightMode)
            }
            .onChange(of: settings.useLightMode) { _, useLight in
                applyAppearance(useLight: useLight)
            }
            .background(DebugWindowController(enabled: $lucidaDebugEnabled))
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
            // Add to the standard View menu (appears under "Show/Hide
            // Sidebar"). Using CommandGroup avoids creating a duplicate
            // top-level "View" menu next to the system one.
            CommandGroup(after: .sidebar) {
                Divider()
                Toggle("Enable Debugging", isOn: $lucidaDebugEnabled)
                    .keyboardShortcut("d", modifiers: [.command, .option])
            }
        }

        // Auxiliary debug window for the Lucida WebKit bridge. Hidden by
        // default; toggled from View → "Enable Debugging".
        Window("Lucida Debug", id: "lucida-debug") {
            LucidaDebugView()
                .environment(lucidaController)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentSize)

        // Menu bar mini-player. The `isInserted` binding reflects the Settings
        // toggle live (Settings is @Observable), so flipping the option in
        // Settings adds/removes the menu bar icon without needing a restart.
        MenuBarExtra(isInserted: menuBarBinding) {
            MenuBarPlayerView()
                .environment(library)
                .environment(player)
                .environment(settings)
                .environment(playlistStore)
                .environment(playlistAddCoordinator)
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
            // Step aside while the lyrics sync sheet is capturing beat taps.
            if player.isLyricsSyncActive {
                return event
            }
            player.engine.togglePlayPause()
            return nil // consume the event
        }
    }

    /// Force the app-wide NSAppearance so AppKit-backed surfaces (MenuBarExtra,
    /// Picker menus, NSColor dynamic providers) flip alongside SwiftUI's
    /// `.preferredColorScheme`.
    private func applyAppearance(useLight: Bool) {
        NSApplication.shared.appearance = NSAppearance(named: useLight ? .aqua : .darkAqua)
    }

    @MainActor
    private func bootstrap() async {
        artistStore.load()
        artistRemoteCache.load()
        lyricsRemoteCache.load()
        player.engine.setVolume(settings.volume)
        discordPresence.attach(player: player, settings: settings)
        if let path = settings.lastRootPath {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                library.openFolder(url)
                playlistStore.load(from: url)
                return
            }
        }
        // Nothing to scan — reveal the UI immediately so the empty state shows.
        withAnimation(.easeOut(duration: 0.35)) {
            library.hasCompletedInitialLoad = true
        }
    }
}
