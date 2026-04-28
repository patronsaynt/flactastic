import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(PlayerState.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(ImportCoordinator.self) private var importCoordinator
    @Environment(PlaylistAddCoordinator.self) private var playlistAddCoordinator
    @Environment(NavigationRouter.self) private var router
    @Environment(ArtistStore.self) private var artistStore
    @Environment(ArtistImageFetcher.self) private var artistImageFetcher
    @Environment(Settings.self) private var settings

    @State private var showSettings = false

    var body: some View {
        @Bindable var router = router
        ZStack {
            Group {
                switch router.selectedTab {
                case .collection:
                    CollectionView()
                case .playlists:
                    PlaylistsTabView()
                case .visualizer:
                    VisualizerView()
                }
            }
            .id(router.selectedTab)
            .transition(.opacity)

            // Opaque cover that hides the populating grid/list during the
            // initial library scan. Fades out once the first load resolves.
            if !library.hasCompletedInitialLoad {
                LoadingCoverView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: library.hasCompletedInitialLoad) { _, done in
            if done { prefetchArtistImages() }
        }
        .task {
            if library.hasCompletedInitialLoad { prefetchArtistImages() }
        }
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                TabBarView(selectedTab: $router.selectedTab)
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
        .overlay(alignment: .bottomTrailing) {
            if player.isQueueVisible {
                QueuePanelView()
                    .frame(width: 340)
                    .padding(.top, Theme.Spacing.lg)
                    .padding(.trailing, Theme.Spacing.lg)
                    .padding(.bottom, 16)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            FloatingPlayerBar()
                .frame(maxWidth: 700)
                .padding(.bottom, 16)
                .offset(x: player.isQueueVisible ? -180 : 0)
        }
        .animation(.easeInOut(duration: 0.28), value: player.isQueueVisible)
        .background(Theme.background)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: Binding(
            get: { importCoordinator.active },
            set: { if $0 == nil { importCoordinator.dismiss() } }
        )) { mode in
            switch mode {
            case .track:    ImportTrackView()
            case .album:    ImportAlbumView()
            case .playlist: ImportPlaylistView()
            }
        }
        .confirmationDialog(
            duplicateDialogTitle,
            isPresented: Binding(
                get: { playlistAddCoordinator.pending != nil },
                set: { if !$0 { playlistAddCoordinator.cancel() } }
            ),
            titleVisibility: .visible,
            presenting: playlistAddCoordinator.pending
        ) { pending in
            if pending.newCount > 0 {
                Button("Skip Duplicates (Add \(pending.newCount))") {
                    playlistAddCoordinator.resolveSkipDuplicates(store: playlistStore)
                }
            }
            Button("Add Anyway") {
                playlistAddCoordinator.resolveAddAll(store: playlistStore)
            }
            Button("Cancel", role: .cancel) {
                playlistAddCoordinator.cancel()
            }
        } message: { pending in
            Text(duplicateDialogMessage(for: pending))
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

    /// Kick off a background pass over every artist in the library so their
    /// images are ready before the user opens the Artists tab. Cheap when
    /// the cache is already warm — `ensureImage` no-ops on hits.
    private func prefetchArtistImages() {
        guard settings.autoFetchArtistImages else { return }
        let resolver = library.makeArtistResolver()
        let summaries = library.allArtists(resolver: resolver, overrides: artistStore.overrides)
        let artists = summaries.map { (key: $0.id, displayName: $0.displayName) }
        artistImageFetcher.prefetchAll(artists)
    }

    private var duplicateDialogTitle: String {
        guard let p = playlistAddCoordinator.pending else { return "" }
        return p.duplicateCount == p.totalCount
            ? "Already in Playlist"
            : "Duplicate Tracks"
    }

    private func duplicateDialogMessage(for p: PlaylistAddCoordinator.PendingAdd) -> String {
        if p.duplicateCount == p.totalCount {
            let noun = p.totalCount == 1 ? "track is" : "tracks are"
            return "All \(p.totalCount) \(noun) already in \"\(p.playlistName)\"."
        }
        let dupNoun = p.duplicateCount == 1 ? "track" : "tracks"
        return "\(p.duplicateCount) of \(p.totalCount) \(dupNoun) are already in \"\(p.playlistName)\"."
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
        // Note: we keep `engine.setQueue` here (not `startFreshQueue`) because
        // repeat-all replays the same queue, so user-queued markers must survive.
    }
}
