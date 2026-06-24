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
    @State private var renamingPlaylistID: UUID?
    @State private var renameText = ""
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
        @Bindable var router = router
        NavigationStack(path: $router.playlistsPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    if settings.useListLayout {
                        playlistList
                    } else {
                        playlistGrid
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Theme.background)
            .navigationDestination(for: UUID.self) { playlistID in
                PlaylistDetailView(playlistID: playlistID)
            }
        }
        .sheet(isPresented: $showNewPlaylistPrompt) {
            newPlaylistSheet
        }
        .sheet(item: $renamingPlaylistID) { playlistID in
            renamePlaylistSheet(for: playlistID)
        }
        .sheet(item: $editingPlaylistID) { playlistID in
            PlaylistEditorView(playlistID: playlistID)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)

                Text("PLAYLISTS — \(filteredPlaylists.count)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(1.5)
            }

            Spacer()

            HStack(spacing: Theme.Spacing.md) {
                Picker("Sort", selection: $sortOption) {
                    ForEach(PlaylistSortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.textSecondary)

                Button {
                    newPlaylistName = ""
                    showNewPlaylistPrompt = true
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                        Text("New Playlist")
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

                SearchBarView(searchText: $searchText)
            }
        }
    }

    // MARK: - Playlist Grid

    private var playlistGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: Theme.Spacing.lg)],
            spacing: Theme.Spacing.xl
        ) {
            ForEach(Array(filteredPlaylists.enumerated()), id: \.element.id) { index, playlist in
                let resolved = playlistStore.resolvedTracks(for: playlist, in: library)
                NavigationLink(value: playlist.id) {
                    PlaylistCardView(
                        playlist: playlist,
                        artwork: playlist.customArtwork ?? resolved.first?.artwork,
                        trackCount: resolved.count
                    )
                }
                .buttonStyle(.plain)
                .flContextMenu { playlistContextMenu(playlist, tracks: resolved) }
                .riseFadeIn(index: index)
            }
        }
    }

    // MARK: - Playlist List

    private var playlistList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredPlaylists.enumerated()), id: \.element.id) { index, playlist in
                let resolved = playlistStore.resolvedTracks(for: playlist, in: library)
                NavigationLink(value: playlist.id) {
                    PlaylistRowView(
                        playlist: playlist,
                        artwork: playlist.customArtwork ?? resolved.first?.artwork,
                        trackCount: resolved.count
                    )
                }
                .buttonStyle(.plain)
                .flContextMenu { playlistContextMenu(playlist, tracks: resolved) }
                .riseFadeIn(index: index)
            }
        }
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

    // MARK: - Rename Playlist Sheet

    private func renamePlaylistSheet(for playlistID: UUID) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("Rename Playlist")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.textPrimary)

            TextField("Playlist name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { commitRename(for: playlistID) }

            HStack(spacing: Theme.Spacing.md) {
                Button("Cancel") {
                    renamingPlaylistID = nil
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    commitRename(for: playlistID)
                }
                .buttonStyle(PillButtonStyle(isPrimary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func commitRename(for playlistID: UUID) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        playlistStore.renamePlaylist(id: playlistID, name: trimmed)
        renamingPlaylistID = nil
    }
}

// MARK: - Make UUID work with .sheet(item:)

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
