import SwiftUI

struct PlaylistDetailView: View {
    let playlistID: UUID

    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player
    @Environment(NavigationRouter.self) private var router

    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var selection: Set<UUID> = []
    @State private var showEditor = false
    @State private var draggingEntryID: UUID? = nil
    @State private var dropTargetEntryID: UUID? = nil

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
            .sheet(isPresented: $showEditor) {
                PlaylistEditorView(playlistID: playlistID)
            }
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
            ArtworkView(data: playlist.customArtwork ?? tracks.first?.artwork, size: 200)

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

                if let desc = playlist.description, !desc.isEmpty {
                    Text(desc)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                HStack(spacing: Theme.Spacing.md) {
                    if !tracks.isEmpty {
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

                    Button {
                        showEditor = true
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "pencil")
                            Text("Edit")
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }
        }
        .frame(minHeight: 200)
    }

    // MARK: - Track List

    @ViewBuilder
    private func trackList(_ playlist: Playlist) -> some View {
        let tracksByPath = buildTrackLookup()

        // SwiftUI's List `.onMove` is unreliable on macOS with `.listStyle(.plain)`,
        // so reordering is implemented with `.draggable` / `.dropDestination`
        // on a LazyVStack instead.
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(playlist.entries.enumerated()), id: \.element.id) { index, entry in
                if let track = resolveEntry(entry, lookup: tracksByPath) {
                    draggablePlaylistRow(
                        entry: entry,
                        track: track,
                        index: index,
                        playlist: playlist
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func draggablePlaylistRow(entry: PlaylistEntry,
                                      track: Track,
                                      index: Int,
                                      playlist: Playlist) -> some View {
        let entryID = entry.id
        let isDropTarget = dropTargetEntryID == entryID && draggingEntryID != entryID
        let rowBackground: Color = player.currentTrack?.id == track.id
            ? Theme.surfaceElevated
            : (selection.contains(entryID) ? Theme.surfaceElevated.opacity(0.6) : Color.clear)

        TrackRow(track: track,
                 isPlaying: player.currentTrack?.id == track.id,
                 displayNumber: index + 1,
                 showDragHandle: true)
            .padding(.vertical, 2)
            .background(rowBackground)
            .opacity(draggingEntryID == entryID ? 0.4 : 1.0)
            .overlay(alignment: .top) {
                if isDropTarget {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(height: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                playFromEntry(entry, in: playlist)
            }
            .flContextMenu { contextMenuItems(for: entry, track: track) }
            .draggable(entryID.uuidString) {
                TrackRow(track: track,
                         isPlaying: false,
                         displayNumber: index + 1,
                         showDragHandle: true)
                    .frame(width: 360)
                    .background(Theme.surfaceElevated)
                    .cornerRadius(Theme.Radius.sm)
                    .onAppear { draggingEntryID = entryID }
                    .onDisappear {
                        draggingEntryID = nil
                        dropTargetEntryID = nil
                    }
            }
            .dropDestination(for: String.self) { items, _ in
                dropTargetEntryID = nil
                draggingEntryID = nil
                guard let s = items.first, let srcID = UUID(uuidString: s) else {
                    return false
                }
                playlistStore.moveEntry(id: srcID, before: entryID, in: playlistID)
                return true
            } isTargeted: { hovering in
                dropTargetEntryID = hovering ? entryID : (dropTargetEntryID == entryID ? nil : dropTargetEntryID)
            }
    }

    // MARK: - Context Menu

    private func contextMenuItems(for entry: PlaylistEntry, track: Track) -> [FLContextMenuItem] {
        var items = playbackContextMenuItems(for: [track], player: player)
        items.append(.divider)
        items.append(.button("View Album", systemImage: "square.grid.2x2") {
            if let albumID = library.album(for: track)?.id {
                router.navigateToAlbum(id: albumID)
            }
        })
        items.append(.divider)

        let selectedCount = selection.contains(entry.id) ? selection.count : 0
        if selectedCount > 1 {
            items.append(.button("Remove \(selectedCount) Tracks", destructive: true) {
                playlistStore.removeEntries(ids: selection, from: playlistID)
                selection = []
            })
        } else {
            items.append(.button("Remove from Playlist", destructive: true) {
                playlistStore.removeEntries(ids: [entry.id], from: playlistID)
                selection.remove(entry.id)
            })
        }
        return items
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
