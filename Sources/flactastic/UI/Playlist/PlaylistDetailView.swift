import SwiftUI

struct PlaylistDetailView: View {
    let playlistID: UUID

    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player

    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var selection: Set<UUID> = []

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
                        trackList(playlist)
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
                            player.isShuffleEnabled = false
                            player.startFreshQueue(tracks, startAt: 0, source: playlist.name)
                            player.engine.play()
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "play.fill")
                                Text("Play All")
                            }
                        }
                        .buttonStyle(PillButtonStyle(isPrimary: true))

                        Button {
                            player.setOriginalQueue(tracks)
                            var shuffled = tracks
                            shuffled.shuffle()
                            player.isShuffleEnabled = true
                            player.startFreshQueue(shuffled, startAt: 0, source: playlist.name)
                            player.engine.play()
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "shuffle")
                                Text("Shuffle")
                            }
                        }
                        .buttonStyle(PillButtonStyle())
                    }
                }
            }
        }
        .frame(height: 200)
    }

    // MARK: - Track List

    @ViewBuilder
    private func trackList(_ playlist: Playlist) -> some View {
        let tracksByPath = buildTrackLookup()

        List(selection: $selection) {
            ForEach(Array(playlist.entries.enumerated()), id: \.element.id) { index, entry in
                if let track = resolveEntry(entry, lookup: tracksByPath) {
                    TrackRow(track: track, isPlaying: player.currentTrack?.id == track.id, displayNumber: index + 1, showDragHandle: true)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            playFromEntry(entry, in: playlist)
                        }
                        .contextMenu {
                            contextMenuItems(for: entry, track: track)
                        }
                        .listRowBackground(
                            player.currentTrack?.id == track.id
                                ? Theme.surfaceElevated
                                : (selection.contains(entry.id)
                                   ? Theme.surfaceElevated.opacity(0.6)
                                   : Color.clear)
                        )
                        .listRowSeparator(.hidden)
                        .tag(entry.id)
                }
            }
            .onMove { source, destination in
                playlistStore.moveEntries(from: source, to: destination, in: playlistID)
            }
            .onDelete { offsets in
                playlistStore.removeEntries(at: offsets, from: playlistID)
                selection = []
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(minHeight: CGFloat(playlist.entries.count) * 48)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for entry: PlaylistEntry, track: Track) -> some View {
        playbackContextMenuItems(for: [track], player: player)
        Divider()

        let selectedCount = selection.contains(entry.id) ? selection.count : 0
        if selectedCount > 1 {
            Button("Remove \(selectedCount) Tracks", role: .destructive) {
                playlistStore.removeEntries(ids: selection, from: playlistID)
                selection = []
            }
        } else {
            Button("Remove from Playlist", role: .destructive) {
                playlistStore.removeEntries(ids: [entry.id], from: playlistID)
                selection.remove(entry.id)
            }
        }
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

    // MARK: - Helpers

    private func buildTrackLookup() -> [String: Track] {
        guard let rootURL = library.rootURL else { return [:] }
        _ = rootURL // rootURL needed for resolution
        return Dictionary(library.tracks.map { ($0.url.path, $0) },
                          uniquingKeysWith: { first, _ in first })
    }

    private func resolveEntry(_ entry: PlaylistEntry, lookup: [String: Track]) -> Track? {
        guard let rootURL = library.rootURL else { return nil }
        let absolutePath = rootURL.appendingPathComponent(entry.relativePath).path
        return lookup[absolutePath]
    }

    private func playFromEntry(_ entry: PlaylistEntry, in playlist: Playlist) {
        let tracks = playlistStore.resolvedTracks(for: playlist, in: library)
        guard let entryIndex = playlist.entries.firstIndex(where: { $0.id == entry.id }) else { return }

        // Map the entry index to the resolved track index (accounting for any
        // unresolvable entries that compactMap skipped).
        var resolvedIndex = 0
        let tracksByPath = buildTrackLookup()
        for i in 0..<entryIndex {
            if resolveEntry(playlist.entries[i], lookup: tracksByPath) != nil {
                resolvedIndex += 1
            }
        }

        guard resolvedIndex < tracks.count else { return }
        player.startFreshQueue(tracks, startAt: resolvedIndex, source: playlist.name)
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
