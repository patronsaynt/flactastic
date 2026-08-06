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
    @Environment(PlaylistAddCoordinator.self) private var playlistAddCoordinator
    @Environment(NavigationRouter.self) private var router

    let tracks: [Track]
    let searchText: String

    /// Persisted across launches. Default stays `.dateAdded` for first-time
    /// users; subsequent runs honour whatever was last picked.
    @AppStorage("flactastic.allTracksSort") private var sortOption: AllTracksSortOption = .dateAdded
    /// `false` for `.dateAdded` means newest-first (the natural default for a
    /// "recently added" sort). For alphabetical sorts the default flips to
    /// ascending (A→Z) via `.onChange` below. Persisted alongside `sortOption`.
    @AppStorage("flactastic.allTracksAscending") private var ascending: Bool = false
    @State private var editingTrack: Track? = nil
    @State private var selection: Set<UUID> = []
    /// Anchor row for shift-click range selection.
    @State private var anchorID: UUID? = nil
    @State private var mergePayload: MergeSheetPayload? = nil
    /// Gates the initial bulk reveal — see `CollectionView.canAnimateEntrances`.
    @State private var canAnimateEntrances = false
    private var animatedTrackIDs: Binding<Set<UUID>> {
        Binding(get: { library.revealedTrackIDs }, set: { library.revealedTrackIDs = $0 })
    }

    /// Cached sorted+filtered track list. Recomputed only when the underlying
    /// inputs change (tracks, search text, sort option, direction) — NOT on
    /// every selection toggle. Without this cache, every tap would re-sort the
    /// entire library, producing seconds-long lag on large collections.
    @State private var cachedVisible: [Track] = []

    private func recomputeVisible() {
        let filtered: [Track]
        if searchText.isEmpty {
            filtered = tracks
        } else {
            let q = searchText.lowercased()
            filtered = tracks.filter { t in
                t.title.localizedCaseInsensitiveContains(q)
                    || (t.artist?.localizedCaseInsensitiveContains(q) ?? false)
                    || (t.album?.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        cachedVisible = sorted(filtered, by: sortOption, ascending: ascending)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            controls

            if cachedVisible.isEmpty {
                emptyState
            } else {
                trackList
            }
        }
        .task { canAnimateEntrances = true }
        .onAppear { recomputeVisible() }
        .onChange(of: tracks) { _, _ in recomputeVisible() }
        .onChange(of: searchText) { _, _ in recomputeVisible() }
        .onChange(of: sortOption) { _, _ in recomputeVisible() }
        .onChange(of: ascending) { _, _ in recomputeVisible() }
        .sheet(item: $editingTrack) { track in
            TrackMetadataEditorView(track: track)
                .environment(library)
        }
        .sheet(item: $mergePayload) { payload in
            MergeTracksIntoAlbumView(tracks: payload.tracks) {
                clearSelection()
            }
            .environment(library)
        }
    }

    private struct MergeSheetPayload: Identifiable {
        let id = UUID()
        let tracks: [Track]
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
            .disabled(cachedVisible.isEmpty)

            Button { playAll(shuffle: true) } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "shuffle")
                    Text("Shuffle All")
                }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(cachedVisible.isEmpty)

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
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(cachedVisible.enumerated()), id: \.element.id) { index, track in
                    TrackRow(
                        track: track,
                        isPlaying: player.currentTrack?.id == track.id,
                        displayNumber: nil,
                        showAlbumArt: true
                    )
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(rowBackground(for: track))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { play(track: track) }
                    .simultaneousGesture(
                        TapGesture(count: 1).onEnded { handleSelection(for: track) }
                    )
                    .flContextMenu {
                        let tracksForMenu = contextTracks(primary: track)
                        playbackContextMenuItems(for: tracksForMenu, player: player)
                        FLContextMenuItem.divider
                        FLContextMenuItem.button("View Album", systemImage: "square.grid.2x2") {
                            if let albumID = library.album(for: track)?.id {
                                router.navigateToAlbum(id: albumID)
                            }
                        }
                        FLContextMenuItem.divider
                        if tracksForMenu.count >= 2 {
                            FLContextMenuItem.button("Merge into Album…") {
                                mergePayload = MergeSheetPayload(tracks: tracksForMenu)
                            }
                            FLContextMenuItem.divider
                        }
                        FLContextMenuItem.button("Edit...", systemImage: "pencil") { editingTrack = track }
                        FLContextMenuItem.divider
                        addToPlaylistMenuItem(tracks: tracksForMenu)
                        let artistItems = artistContextMenuItems(
                            credit: track.artist ?? track.albumArtist,
                            library: library,
                            router: router
                        )
                        if !artistItems.isEmpty {
                            FLContextMenuItem.divider
                            artistItems
                        }
                    }
                    .riseFadeIn(index: index, animated: track.id, animatedIDs: animatedTrackIDs, enabled: canAnimateEntrances)
                }
            }
            .padding(.bottom, 100)
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { clearSelection() }
            )
        }
    }

    /// Tracks the context menu should operate on. When the right-clicked track
    /// is part of an active multi-selection, include every selected track so
    /// "Merge into Album…" and other batch actions target the whole set.
    /// Otherwise the menu acts on the single right-clicked track.
    private func contextTracks(primary: Track) -> [Track] {
        if selection.count >= 2, selection.contains(primary.id) {
            let byID = Dictionary(uniqueKeysWithValues: cachedVisible.map { ($0.id, $0) })
            return selection.compactMap { byID[$0] }
        }
        return [primary]
    }

    private func handleSelection(for track: Track) {
        if NSEvent.modifierFlags.contains(.shift) {
            // Shift-click: extend selection from anchor (or current row if none)
            // to the clicked row.
            let anchor = anchorID ?? track.id
            guard let anchorIdx = cachedVisible.firstIndex(where: { $0.id == anchor }),
                  let clickedIdx = cachedVisible.firstIndex(where: { $0.id == track.id })
            else { return }
            let lo = min(anchorIdx, clickedIdx)
            let hi = max(anchorIdx, clickedIdx)
            selection = Set(cachedVisible[lo...hi].map(\.id))
            if anchorID == nil { anchorID = track.id }
        } else {
            // Plain click: select only this row and set it as the range anchor.
            selection = [track.id]
            anchorID = track.id
        }
    }

    private func clearSelection() {
        if !selection.isEmpty { selection = [] }
        anchorID = nil
    }

    @ViewBuilder
    private func rowBackground(for track: Track) -> some View {
        let isPlaying = player.currentTrack?.id == track.id
        let isSelected = selection.contains(track.id)
        if isPlaying {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Theme.surfaceElevated)
        } else if isSelected {
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Theme.surfaceElevated.opacity(0.55))
        } else {
            Color.clear
        }
    }

    private func addToPlaylistMenuItem(tracks: [Track]) -> FLContextMenuItem {
        var children: [FLContextMenuItem] = []
        if !playlistStore.playlists.isEmpty {
            for playlist in playlistStore.playlists {
                children.append(.button(playlist.name) {
                    playlistAddCoordinator.request(
                        tracks: tracks,
                        playlistID: playlist.id,
                        playlistName: playlist.name,
                        rootURL: library.rootURL,
                        store: playlistStore
                    )
                })
            }
            children.append(.divider)
        }
        children.append(.textField("New playlist name…", systemImage: "plus") { name in
            playlistAddCoordinator.createPlaylistAndAdd(
                name: name,
                tracks: tracks,
                rootURL: library.rootURL,
                store: playlistStore
            )
        })
        return .submenu("Add to Playlist", systemImage: "plus.square.on.square", items: children)
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

    private func play(track: Track) {
        let queue = cachedVisible
        guard let index = queue.firstIndex(where: { $0.id == track.id }) else { return }
        player.startFreshQueue(queue, startAt: index, source: "Library")
        player.engine.play()
        clearSelection()
    }

    private func playAll(shuffle: Bool) {
        let queue = cachedVisible
        guard !queue.isEmpty else { return }
        player.isShuffleEnabled = shuffle
        let startIndex = shuffle ? Int.random(in: 0..<queue.count) : 0
        player.startFreshQueue(queue, startAt: startIndex, source: "Library")
        player.engine.play()
        clearSelection()
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
