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

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    playlistHeader(playlist, tracks: tracks)

                    if tracks.isEmpty {
                        emptyState
                    } else {
                        trackList(tracks)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Theme.background)
            .navigationTitle(playlist.name)
        } else {
            Text("Playlist not found")
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func playlistHeader(_ playlist: Playlist, tracks: [Track]) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            // Playlist artwork (first track's artwork or placeholder)
            ArtworkView(data: tracks.first?.artwork, size: 200)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if isEditingName {
                    TextField("Playlist name", text: $editedName)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.textPrimary)
                        .onSubmit { commitRename() }
                } else {
                    Text(playlist.name)
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.textPrimary)
                        .onTapGesture(count: 2) {
                            editedName = playlist.name
                            isEditingName = true
                        }
                }

                Text("\(tracks.count) track\(tracks.count == 1 ? "" : "s")")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                if !tracks.isEmpty {
                    HStack(spacing: Theme.Spacing.md) {
                        Button {
                            player.engine.setQueue(tracks, startAt: 0)
                            player.engine.play()
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12))
                                Text("Play All")
                            }
                        }
                        .buttonStyle(PrimaryMonochromeButtonStyle())

                        Button {
                            var shuffled = tracks
                            shuffled.shuffle()
                            player.isShuffleEnabled = true
                            player.engine.setQueue(shuffled, startAt: 0)
                            player.engine.play()
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 12))
                                Text("Shuffle")
                            }
                        }
                        .buttonStyle(MonochromeButtonStyle())
                    }
                }
            }
        }
        .frame(height: 200)
    }

    // MARK: - Track List

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
        .frame(minHeight: CGFloat(tracks.count) * 48)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textTertiary)
            Text("No tracks in this playlist")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textTertiary)
            Text("Right-click tracks in your collection to add them")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xxl)
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
