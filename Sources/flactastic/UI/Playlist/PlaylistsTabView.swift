import SwiftUI

enum PlaylistSortOption: String, CaseIterable, Identifiable {
    case nameAsc = "A → Z"
    case nameDesc = "Z → A"
    case dateCreated = "Newest"

    var id: String { rawValue }
}

struct PlaylistsTabView: View {
    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player
    @Environment(Settings.self) private var settings
    @Environment(NavigationRouter.self) private var router

    @State private var searchText = ""
    @State private var sortOption: PlaylistSortOption = .nameAsc
    @State private var showNewPlaylistPrompt = false
    @State private var newPlaylistName = ""
    @State private var editingPlaylistID: UUID?

    private var filteredPlaylists: [Playlist] {
        let sorted: [Playlist]
        switch sortOption {
        case .nameAsc:
            sorted = playlistStore.playlists.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .nameDesc:
            sorted = playlistStore.playlists.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedDescending
            }
        case .dateCreated:
            sorted = playlistStore.playlists.sorted { $0.dateCreated > $1.dateCreated }
        }

        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        // Manual navigation (no NavigationStack) — see CollectionView for why.
        Group {
            if let playlistID = router.playlistsPath.last {
                PlaylistDetailView(playlistID: playlistID)
                    .transition(.opacity)
            } else {
                rootContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: router.playlistsPath)
        .sheet(isPresented: $showNewPlaylistPrompt) {
            newPlaylistSheet
        }
        .sheet(item: $editingPlaylistID) { playlistID in
            PlaylistEditorView(playlistID: playlistID)
        }
    }

    private var rootContent: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                FLPageHeader(eyebrow: "Library", title: "Playlists")
                    .padding(.top, 30)

                controlRow
                    .padding(.top, 18)
                    .padding(.bottom, 20 - cardHoverHeadroom)
            }
            .padding(.horizontal, collectionGutter)

            ScrollView {
                Group {
                    if settings.useListLayout {
                        playlistList
                    } else {
                        playlistGrid
                    }
                }
                .transition(.opacity)
                .padding(.horizontal, collectionGutter)
                .padding(.top, cardHoverHeadroom)
                .padding(.bottom, 100)
            }
            .animation(.easeInOut(duration: 0.22), value: settings.useListLayout)
        }
        .background(Theme.background)
    }

    // MARK: - Control row

    /// Same persisted app-wide preference the Collection tab drives.
    private var useListLayout: Binding<Bool> {
        Binding(get: { settings.useListLayout }, set: { settings.useListLayout = $0 })
    }

    private var controlRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                newPlaylistName = ""
                showNewPlaylistPrompt = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("New Playlist")
                }
            }
            .buttonStyle(FLActionPillStyle(isPrimary: true, height: 34))

            FLPillToggle(
                selection: useListLayout,
                segments: [
                    .icon(false, "square.grid.2x2", help: "Grid"),
                    .icon(true, "list.bullet", help: "List"),
                ]
            )

            Spacer()

            FLSortMenu(
                selection: $sortOption,
                options: PlaylistSortOption.allCases
            ) { $0.rawValue }

            SearchBarView(searchText: $searchText, style: .capsule)
        }
    }

    // MARK: - Playlist Grid

    private var playlistGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 24)],
            spacing: 24
        ) {
            ForEach(Array(filteredPlaylists.enumerated()), id: \.element.id) { index, playlist in
                let resolved = playlistStore.resolvedTracks(for: playlist, in: library)
                PlaylistCardView(
                    playlist: playlist,
                    artwork: playlist.customArtwork ?? resolved.first?.artwork,
                    trackCount: resolved.count,
                    totalDuration: totalDuration(of: resolved)
                )
                .contentShape(Rectangle())
                .onTapGesture { router.playlistsPath.append(playlist.id) }
                .flContextMenu { playlistContextMenu(playlist, tracks: resolved) }
                .riseFadeIn(index: index)
            }
        }
    }

    // MARK: - Playlist List

    private var playlistList: some View {
        LazyVStack(spacing: 2) {
            ForEach(Array(filteredPlaylists.enumerated()), id: \.element.id) { index, playlist in
                let resolved = playlistStore.resolvedTracks(for: playlist, in: library)
                PlaylistRowView(
                    playlist: playlist,
                    artwork: playlist.customArtwork ?? resolved.first?.artwork,
                    trackCount: resolved.count,
                    totalDuration: totalDuration(of: resolved)
                )
                .onTapGesture { router.playlistsPath.append(playlist.id) }
                .flContextMenu { playlistContextMenu(playlist, tracks: resolved) }
                .riseFadeIn(index: index)
            }
        }
    }

    private func totalDuration(of tracks: [Track]) -> TimeInterval {
        tracks.reduce(0) { $0 + ($1.duration ?? 0) }
    }

    private func playlistContextMenu(_ playlist: Playlist, tracks: [Track]) -> [FLContextMenuItem] {
        var items = playbackContextMenuItems(for: tracks, player: player)
        items.append(.divider)
        items.append(.button("Edit…", systemImage: "pencil") { editingPlaylistID = playlist.id })
        items.append(.divider)
        items.append(.button("Delete", destructive: true) {
            playlistStore.deletePlaylist(id: playlist.id)
        })
        return items
    }

    // MARK: - New Playlist Sheet

    private var newPlaylistSheet: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("New Playlist")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.textPrimary)

            TextField("Playlist name", text: $newPlaylistName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { commitNewPlaylist() }

            HStack(spacing: Theme.Spacing.md) {
                Button("Cancel") {
                    showNewPlaylistPrompt = false
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    commitNewPlaylist()
                }
                .buttonStyle(PillButtonStyle(isPrimary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 340, height: 160)
        .background(Theme.surface)
    }

    // MARK: - Actions

    private func commitNewPlaylist() {
        let trimmed = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        playlistStore.createPlaylist(name: trimmed)
        showNewPlaylistPrompt = false
    }
}

// MARK: - Make UUID work with .sheet(item:)

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
