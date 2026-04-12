import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(PlayerState.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(PlaylistStore.self) private var playlistStore

    @State private var selectedTab: AppTab = .collection
    @State private var showSettings = false

    var body: some View {
        Group {
            switch selectedTab {
            case .collection:
                CollectionView()
            case .playlists:
                PlaylistsTabView()
            case .visualizer:
                VisualizerView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                TabBarView(selectedTab: $selectedTab)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                        Text("Settings")
                            .font(Theme.Font.caption)
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .toolbarBackground(Theme.background, for: .windowToolbar)
        .overlay(alignment: .bottom) {
            FloatingPlayerBar()
                .frame(maxWidth: 700)
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
            // Handle repeat only when playback stopped naturally (track reached the end),
            // not when the user manually pressed pause.
            if oldValue && !newValue && player.currentTrack != nil {
                let reachedEnd: Bool
                if let duration = player.duration, duration > 0 {
                    reachedEnd = player.currentTime >= duration - 0.5
                } else {
                    reachedEnd = false
                }
                if reachedEnd {
                    handleRepeat()
                }
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
            if !queue.isEmpty {
                player.engine.setQueue(queue, startAt: 0)
                player.engine.play()
            }
        }
    }
}
