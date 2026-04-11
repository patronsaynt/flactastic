import SwiftUI

enum PlaylistSortOption: String, CaseIterable, Identifiable {
    case nameAsc = "A → Z"
    case nameDesc = "Z → A"
    case dateCreated = "Newest"

    var id: String { rawValue }
}

struct PlaylistsTabView: View {
    let searchText: String

    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(LibraryStore.self) private var library

    @State private var sortOption: PlaylistSortOption = .nameAsc

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    playlistGrid
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
                    playlistStore.createPlaylist(name: "New Playlist")
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
            }
        }
    }

    // MARK: - Playlist Grid

    private var playlistGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: Theme.Spacing.lg)],
            spacing: Theme.Spacing.xl
        ) {
            ForEach(filteredPlaylists) { playlist in
                let resolved = playlistStore.resolvedTracks(for: playlist, in: library)
                NavigationLink(value: playlist.id) {
                    PlaylistCardView(
                        playlist: playlist,
                        artwork: resolved.first?.artwork,
                        trackCount: resolved.count
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        playlistStore.deletePlaylist(id: playlist.id)
                    }
                }
            }
        }
    }
}
