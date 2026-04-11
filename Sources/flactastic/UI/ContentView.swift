import SwiftUI

struct ContentView: View {
    @Environment(PlayerState.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(PlaylistStore.self) private var playlistStore

    @State private var selectedTab: AppTab = .collection
    @State private var searchText = ""
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            TopNavigationBar(
                selectedTab: $selectedTab,
                searchText: $searchText,
                onSettingsPressed: { showSettings = true }
            )

            Divider().foregroundStyle(Theme.divider)

            // Tab content
            Group {
                switch selectedTab {
                case .collection:
                    CollectionView(searchText: searchText)
                case .playlists:
                    PlaylistsTabView(searchText: searchText)
                case .visualizer:
                    VisualizerView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            FloatingPlayerBar()
                .padding(.horizontal, 40)
                .padding(.bottom, 16)
        }
        .background(Theme.background)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: library.scanState) { _, newState in
            if case .done = newState {
                playlistStore.reconcile(with: library)
            }
        }
        .onChange(of: player.isPlaying) { oldValue, newValue in
            // Handle repeat when playback stops naturally
            if oldValue && !newValue && player.currentTrack != nil {
                handleRepeat()
            }
        }
    }

    private func handleRepeat() {
        switch player.repeatMode {
        case .off:
            break
        case .one:
            player.engine.seek(to: 0)
            player.engine.play()
        case .all:
            let queue = player.queue
            if !queue.isEmpty && player.currentIndex >= queue.count - 1 {
                player.engine.setQueue(queue, startAt: 0)
                player.engine.play()
            }
        }
    }
}
