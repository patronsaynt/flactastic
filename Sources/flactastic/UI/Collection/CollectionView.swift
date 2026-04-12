import SwiftUI

struct CollectionView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player
    @Environment(Settings.self) private var settings

    @State private var searchText = ""
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

    /// Groups albums by the current sort key when sorting by artist or genre.
    private var groupedAlbums: [(key: String, albums: [Album])] {
        let albums = filteredAlbums
        switch sortOption {
        case .artist:
            let grouped = Dictionary(grouping: albums) { $0.artist ?? "Unknown Artist" }
            return grouped.map { (key: $0.key, albums: $0.value) }
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        case .genre:
            let grouped = Dictionary(grouping: albums) { $0.genre ?? "Unknown" }
            return grouped.map { (key: $0.key, albums: $0.value) }
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        default:
            return []
        }
    }

    private var shouldGroup: Bool {
        sortOption == .artist || sortOption == .genre
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

                    if shouldGroup {
                        groupedContent
                    } else if settings.useListLayout {
                        albumList(filteredAlbums)
                    } else {
                        albumGrid(filteredAlbums)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, 100)
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

            SearchBarView(searchText: $searchText)
        }
    }

    // MARK: - Grouped Content

    private var groupedContent: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            ForEach(groupedAlbums, id: \.key) { group in
                Section {
                    if settings.useListLayout {
                        albumList(group.albums)
                    } else {
                        albumGrid(group.albums)
                    }
                } header: {
                    Text(group.key)
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, Theme.Spacing.sm)
                }
            }
        }
    }

    // MARK: - Album Grid

    private func albumGrid(_ albums: [Album]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: Theme.Spacing.lg)],
            spacing: Theme.Spacing.xl
        ) {
            ForEach(albums) { album in
                NavigationLink(value: album.id) {
                    AlbumCardView(album: album)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Album List

    private func albumList(_ albums: [Album]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(albums) { album in
                NavigationLink(value: album.id) {
                    AlbumRowView(album: album)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
