import SwiftUI

struct CollectionView: View {
    let searchText: String

    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player

    @State private var sortOption: CollectionSortOption = .album

    private var filteredAlbums: [Album] {
        let sorted = sortedAlbums
        guard !searchText.isEmpty else { return sorted }
        let query = searchText.lowercased()
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.artist?.localizedCaseInsensitiveContains(query) ?? false) ||
            $0.tracks.contains { $0.title.localizedCaseInsensitiveContains(query) }
        }
    }

    private var sortedAlbums: [Album] {
        let albums = library.albums
        switch sortOption {
        case .album:
            return albums.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .artist:
            return albums.sorted {
                ($0.artist ?? "").localizedStandardCompare($1.artist ?? "") == .orderedAscending
            }
        case .year:
            return albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .genre:
            return albums.sorted {
                ($0.genre ?? "Unknown").localizedStandardCompare($1.genre ?? "Unknown") == .orderedAscending
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    albumGrid
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, 100) // Space for floating player
            }
            .background(Theme.background)
            .navigationDestination(for: String.self) { albumID in
                AlbumDetailView(albumID: albumID)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)

                Text("LIBRARY — \(filteredAlbums.count) ALBUM\(filteredAlbums.count == 1 ? "" : "S")")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(1.5)
            }

            Spacer()

            Picker("Sort", selection: $sortOption) {
                ForEach(CollectionSortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.textSecondary)
        }
    }

    // MARK: - Album Grid

    private var albumGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: Theme.Spacing.lg)],
            spacing: Theme.Spacing.xl
        ) {
            ForEach(filteredAlbums) { album in
                NavigationLink(value: album.id) {
                    AlbumCardView(album: album)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
