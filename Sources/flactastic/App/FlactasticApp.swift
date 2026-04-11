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
                .preferredColorScheme(.dark)
                .frame(minWidth: 1000, minHeight: 650)
                .background(Theme.background)
                .task { await bootstrap() }
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
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
