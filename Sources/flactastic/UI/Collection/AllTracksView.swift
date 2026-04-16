import SwiftUI

/// Flat "All Tracks" view for the Collection tab. Shows every track in the
/// library as a sortable, searchable list, with Play All / Shuffle All buttons
/// that queue the entire (filtered + sorted) catalogue.
///
/// The parent `CollectionView` owns the search text and the mode toggle. This
/// view owns sort state (option + direction), the action buttons, and the list.
struct AllTracksView: View {
    @Environment(PlayerState.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(PlaylistStore.self) private var playlistStore

    let tracks: [Track]
    let searchText: String

    @State private var sortOption: AllTracksSortOption = .dateAdded
    /// `false` for `.dateAdded` means newest-first (the natural default for a
    /// "recently added" sort). For alphabetical sorts the default flips to
    /// ascending (A→Z) via `.onChange` below.
    @State private var ascending: Bool = false
    @State private var editingTrack: Track? = nil

    private var visibleTracks: [Track] {
        let base = filteredTracks
        return sorted(base, by: sortOption, ascending: ascending)
    }

    private var filteredTracks: [Track] {
        guard !searchText.isEmpty else { return tracks }
        let q = searchText.lowercased()
        return tracks.filter { t in
            t.title.localizedCaseInsensitiveContains(q)
                || (t.artist?.localizedCaseInsensitiveContains(q) ?? false)
                || (t.album?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            controls

            if visibleTracks.isEmpty {
                emptyState
            } else {
                trackList
            }
        }
        .sheet(item: $editingTrack) { track in
            TrackMetadataEditorView(track: track)
                .environment(library)
        }
    }

    // MARK: - Controls row

    private var controls: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button { playAll(shuffle: false) } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "play.fill")
                    Text("Play All")
                }
            }
            .buttonStyle(PillButtonStyle(isPrimary: true))
            .disabled(visibleTracks.isEmpty)

            Button { playAll(shuffle: true) } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "shuffle")
                    Text("Shuffle All")
                }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(visibleTracks.isEmpty)

            Spacer()

            Picker("Sort", selection: $sortOption) {
                ForEach(AllTracksSortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.textSecondary)
            .onChange(of: sortOption) { _, newValue in
                // Reset direction to the sensible default for the chosen sort.
                ascending = (newValue != .dateAdded)
            }

            Button {
                ascending.toggle()
            } label: {
                Image(systemName: ascending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(Theme.surfaceElevated)
                    )
            }
            .buttonStyle(.plain)
            .help(ascending ? "Ascending" : "Descending")
        }
    }

    // MARK: - Track list

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(visibleTracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(
                    track: track,
                    isPlaying: player.currentTrack?.id == track.id,
                    displayNumber: nil  // Hide track numbers in all-tracks view
                )
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 2)
                .background(
                    player.currentTrack?.id == track.id
                        ? Theme.surfaceElevated
                        : Color.clear
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    play(at: index)
                }
                .contextMenu {
                    playbackContextMenuItems(for: [track], player: player)
                    Divider()
                    Button("Edit...") { editingTrack = track }
                    Divider()
                    addToPlaylistMenu(track: track)
                }
            }
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

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "music.note.list")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textTertiary)
            Text(tracks.isEmpty ? "No tracks in your library" : "No tracks match your search")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }

    // MARK: - Playback

    private func play(at index: Int) {
        let queue = visibleTracks
        guard queue.indices.contains(index) else { return }
        player.isShuffleEnabled = false
        player.startFreshQueue(queue, startAt: index, source: "Library")
        player.engine.play()
    }

    private func playAll(shuffle: Bool) {
        let queue = visibleTracks
        guard !queue.isEmpty else { return }
        if shuffle {
            // Preserve the sorted order so toggling shuffle off later restores it.
            player.setOriginalQueue(queue)
            var shuffled = queue
            shuffled.shuffle()
            player.isShuffleEnabled = true
            player.startFreshQueue(shuffled, startAt: 0, source: "Library")
        } else {
            player.isShuffleEnabled = false
            player.startFreshQueue(queue, startAt: 0, source: "Library")
        }
        player.engine.play()
    }

    // MARK: - Sorting

    private func sorted(_ tracks: [Track],
                        by option: AllTracksSortOption,
                        ascending: Bool) -> [Track] {
        let result: [Track]
        switch option {
        case .songName:
            result = tracks.sorted { a, b in
                a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        case .artistName:
            result = tracks.sorted { a, b in
                let lhs = a.artist ?? ""
                let rhs = b.artist ?? ""
                if lhs.isEmpty != rhs.isEmpty { return !lhs.isEmpty }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        case .dateAdded:
            // Tracks missing a timestamp sort to the end regardless of order.
            result = tracks.sorted { a, b in
                switch (a.dateAdded, b.dateAdded) {
                case let (x?, y?): return x < y
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return a.title.localizedStandardCompare(b.title) == .orderedAscending
                }
            }
        }
        return ascending ? result : result.reversed()
    }
}
