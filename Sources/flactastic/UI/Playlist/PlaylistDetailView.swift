import SwiftUI

struct PlaylistDetailView: View {
    let playlistID: UUID

    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player

    @State private var isEditingName = false
    @State private var editedName = ""

    private var playlist: Playlist? {
        playlistStore.playlists.first { $0.id == playlistID }
    }

    var body: some View {
        if let playlist {
            let tracks = playlistStore.resolvedTracks(for: playlist, in: library)

            VStack(spacing: 0) {
                playlistHeader(playlist, trackCount: tracks.count)
                Divider().foregroundStyle(Theme.divider)

                if tracks.isEmpty {
                    emptyState
                } else {
                    trackList(tracks)
                }
            }
            .background(Theme.surface)
        } else {
            Text("Playlist not found")
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.surface)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func playlistHeader(_ playlist: Playlist, trackCount: Int) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if isEditingName {
                    TextField("Playlist name", text: $editedName)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .onSubmit {
                            commitRename()
                        }
                } else {
                    Text(playlist.name)
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .onTapGesture(count: 2) {
                            editedName = playlist.name
                            isEditingName = true
                        }
                }

                Text("\(trackCount) track\(trackCount == 1 ? "" : "s")")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if trackCount > 0 {
                Button {
                    let tracks = playlistStore.resolvedTracks(for: playlist, in: library)
                    guard !tracks.isEmpty else { return }
                    player.engine.setQueue(tracks, startAt: 0)
                    player.engine.play()
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Play All")
                            .font(Theme.Font.bodyMedium)
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill(Theme.surfaceElevated)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Track list

    @ViewBuilder
    private func trackList(_ tracks: [Track]) -> some View {
        List {
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                TrackRow(track: track, isPlaying: player.currentTrack?.id == track.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        playTrack(at: index)
                    }
                    .listRowBackground(
                        player.currentTrack?.id == track.id
                            ? Theme.surfaceElevated
                            : Color.clear
                    )
                    .listRowSeparator(.hidden)
            }
            .onMove { source, destination in
                playlistStore.moveTracks(from: source, to: destination, in: playlistID)
            }
            .onDelete { offsets in
                playlistStore.removeTrack(at: offsets, from: playlistID)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textTertiary)
            Text("No tracks in this playlist")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textTertiary)
            Text("Right-click tracks in your library to add them")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    // MARK: - Actions

    private func playTrack(at index: Int) {
        guard let playlist else { return }
        let tracks = playlistStore.resolvedTracks(for: playlist, in: library)
        guard index < tracks.count else { return }
        player.engine.setQueue(tracks, startAt: index)
        player.engine.play()
    }

    private func commitRename() {
        let trimmed = editedName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            playlistStore.renamePlaylist(id: playlistID, name: trimmed)
        }
        isEditingName = false
    }
}
