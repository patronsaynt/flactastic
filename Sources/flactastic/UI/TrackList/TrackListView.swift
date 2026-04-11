import SwiftUI

struct TrackListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player
    @Environment(PlaylistStore.self) private var playlistStore

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
                    .contextMenu {
                        addToPlaylistMenu(track: track)
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
        }
    }

    @ViewBuilder
    private func addToPlaylistMenu(track: Track) -> some View {
        if playlistStore.playlists.isEmpty {
            Text("No playlists yet")
        } else {
            Menu("Add to Playlist") {
                ForEach(playlistStore.playlists) { playlist in
                    Button(playlist.name) {
                        playlistStore.addTracks([track], to: playlist.id, relativeTo: library.rootURL)
                    }
                }
            }
        }
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
        player.engine.setQueue(library.tracks, startAt: index)
        player.engine.play()
    }
}
