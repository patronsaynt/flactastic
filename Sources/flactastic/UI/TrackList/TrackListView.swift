import SwiftUI

struct TrackListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player
    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(NavigationRouter.self) private var router

    @State private var editingTrack: Track? = nil

    var body: some View {
        if library.tracks.isEmpty {
            emptyState
        } else {
            List(library.tracks) { track in
                TrackRow(track: track, isPlaying: player.currentTrack?.id == track.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        play(track)
                    }
                    .flContextMenu {
                        playbackContextMenuItems(for: [track], player: player)
                        FLContextMenuItem.divider
                        FLContextMenuItem.button("View Album", systemImage: "square.grid.2x2") {
                            if let albumID = library.album(for: track)?.id {
                                router.navigateToAlbum(id: albumID)
                            }
                        }
                        FLContextMenuItem.divider
                        FLContextMenuItem.button("Edit...") { editingTrack = track }
                        FLContextMenuItem.divider
                        addToPlaylistMenuItem(track: track)
                    }
                    .listRowBackground(
                        player.currentTrack?.id == track.id
                            ? Theme.surfaceElevated
                            : Color.clear
                    )
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .sheet(item: $editingTrack) { track in
                TrackMetadataEditorView(track: track)
                    .environment(library)
            }
        }
    }

    private func addToPlaylistMenuItem(track: Track) -> FLContextMenuItem {
        if playlistStore.playlists.isEmpty {
            return .label("No playlists yet")
        }
        let children: [FLContextMenuItem] = playlistStore.playlists.map { playlist in
            .button(playlist.name) {
                playlistStore.addTracks([track], to: playlist.id, relativeTo: library.rootURL)
            }
        }
        return .submenu("Add to Playlist", systemImage: "plus.square.on.square", items: children)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textTertiary)
            Text("No tracks yet")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    private func play(_ track: Track) {
        guard let index = library.tracks.firstIndex(where: { $0.id == track.id }) else { return }
        player.startFreshQueue(library.tracks, startAt: index, source: "Library")
        player.engine.play()
    }
}
