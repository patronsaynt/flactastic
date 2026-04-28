import SwiftUI

struct CollectionView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player
    @Environment(Settings.self) private var settings
    @Environment(NavigationRouter.self) private var router
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var sortOption: CollectionSortOption = .album
    @State private var contentMode: CollectionContentMode = .albums
    @State private var editingAlbum: Album? = nil
    @State private var refreshRotation: Double = 0

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

    private var isRefreshing: Bool {
        library.scanState == .refreshing || library.scanState == .scanning
    }

    private var shouldGroup: Bool {
        sortOption == .genre || (sortOption == .artist && settings.groupByArtist)
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.collectionPath) {
            VStack(spacing: 0) {
                // Header is always pinned above the content area.
                header
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.top, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.md)

                switch contentMode {
                case .albums:
                    // Albums use a ScrollView so the grid/list can grow freely.
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            if shouldGroup {
                                groupedContent
                            } else if settings.useListLayout {
                                albumList(filteredAlbums)
                            } else {
                                albumGrid(filteredAlbums)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.bottom, 100)
                    }
                case .tracks:
                    // Tracks uses List internally — omit the outer ScrollView so
                    // List can take full height and scroll on its own.
                    AllTracksView(tracks: library.tracks, searchText: searchText)
                        .padding(.horizontal, Theme.Spacing.xl)
                case .artists:
                    ArtistsCollectionView(searchText: searchText)
                }
            }
            .background(Theme.background)
            .navigationDestination(for: String.self) { value in
                if let artistKey = NavigationRoute.artistKey(from: value) {
                    ArtistDetailView(artistKey: artistKey)
                } else {
                    AlbumDetailView(albumID: value)
                }
            }
            .sheet(item: $editingAlbum) { album in
                AlbumMetadataEditorView(album: album)
                    .environment(library)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Picker("View", selection: $contentMode) {
                ForEach(CollectionContentMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)

                Text(countLabel)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(1.5)
            }

            Button { library.refreshLibrary() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isRefreshing ? Theme.textTertiary : Theme.textSecondary)
                    .rotationEffect(.degrees(refreshRotation))
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            .help("Refresh Library")
            .onChange(of: isRefreshing) { _, spinning in
                if spinning {
                    withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                        refreshRotation = 360
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        refreshRotation = 0
                    }
                }
            }

            Spacer()

            HStack(spacing: Theme.Spacing.md) {
                if contentMode == .albums {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(CollectionSortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.textSecondary)
                    .id(colorScheme)
                }

                SearchBarView(searchText: $searchText)
            }
        }
    }

    private var countLabel: String {
        switch contentMode {
        case .albums:
            let n = filteredAlbums.count
            return "LIBRARY — \(n) ALBUM\(n == 1 ? "" : "S")"
        case .tracks:
            let n = library.tracks.count
            return "LIBRARY — \(n) TRACK\(n == 1 ? "" : "S")"
        case .artists:
            let resolver = library.makeArtistResolver()
            let n = library.allArtists(resolver: resolver).count
            return "LIBRARY — \(n) ARTIST\(n == 1 ? "" : "S")"
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
            ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                NavigationLink(value: album.id) {
                    AlbumCardView(album: album)
                }
                .buttonStyle(.plain)
                .flContextMenu { albumContextMenu(album) }
                .riseFadeIn(index: index)
            }
        }
    }

    // MARK: - Album List

    private func albumList(_ albums: [Album]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                NavigationLink(value: album.id) {
                    AlbumRowView(album: album)
                }
                .buttonStyle(.plain)
                .flContextMenu { albumContextMenu(album) }
                .riseFadeIn(index: index)
            }
        }
    }

    private func albumContextMenu(_ album: Album) -> [FLContextMenuItem] {
        var items = playbackContextMenuItems(for: album.tracks, player: player)
        items.append(.divider)
        items.append(.button("Edit...") { editingAlbum = album })
        if !album.isCompilation {
            let artistItems = artistContextMenuItems(
                credit: album.albumArtist ?? album.artist,
                library: library,
                router: router
            )
            if !artistItems.isEmpty {
                items.append(.divider)
                items.append(contentsOf: artistItems)
            }
        }
        return items
    }
}
