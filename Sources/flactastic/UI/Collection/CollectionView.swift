import SwiftUI

struct CollectionView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player
    @Environment(Settings.self) private var settings
    @Environment(NavigationRouter.self) private var router
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    /// Persisted across launches so the user's preferred grouping (e.g.
    /// "Artist") survives quitting the app. Default stays `.album` for
    /// first-time users.
    @AppStorage("flactastic.collectionSort") private var sortOption: CollectionSortOption = .album
    @State private var contentMode: CollectionContentMode = .albums
    @State private var editingAlbum: Album? = nil
    @State private var refreshRotation: Double = 0
    /// Gates the *initial* bulk reveal of the album grid/list for this
    /// mount: starts `false` so the first synchronous render of however
    /// many cells populate at once shows instantly (animating dozens of
    /// cells simultaneously is itself a source of stutter), then flips
    /// `true` shortly after so anything appearing from then on (search
    /// results, continued scrolling) still gets the fade. Per-item replay
    /// prevention lives on `library.revealedAlbumIDs` instead of local
    /// state, since this view gets fully remounted on every tab switch.
    @State private var canAnimateEntrances = false
    private var animatedAlbumIDs: Binding<Set<String>> {
        Binding(get: { library.revealedAlbumIDs }, set: { library.revealedAlbumIDs = $0 })
    }

    /// Cached sorted+filtered (and, for artist/genre sorts, grouped) album
    /// lists. Recomputed only when the underlying inputs change — NOT on every
    /// body evaluation. Sorting with `localizedStandardCompare` inside `body`
    /// re-sorted the whole library on every render (hover, selection, any
    /// observable tick). Same pattern as `AllTracksView.cachedVisible`.
    @State private var cachedFiltered: [Album] = []
    @State private var cachedGroups: [(key: String, albums: [Album])] = []

    private func recomputeVisible() {
        let albums = library.albums
        let sorted: [Album]
        switch sortOption {
        case .album:
            sorted = albums.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .artist:
            sorted = albums.sorted {
                ($0.artist ?? "").localizedStandardCompare($1.artist ?? "") == .orderedAscending
            }
        case .year:
            sorted = albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .genre:
            sorted = albums.sorted {
                ($0.genre ?? "Unknown").localizedStandardCompare($1.genre ?? "Unknown") == .orderedAscending
            }
        }

        let filtered: [Album]
        if searchText.isEmpty {
            filtered = sorted
        } else {
            let query = searchText.lowercased()
            filtered = sorted.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                ($0.artist?.localizedCaseInsensitiveContains(query) ?? false) ||
                $0.tracks.contains { $0.title.localizedCaseInsensitiveContains(query) }
            }
        }
        cachedFiltered = filtered

        switch sortOption {
        case .artist:
            let grouped = Dictionary(grouping: filtered) { $0.artist ?? "Unknown Artist" }
            cachedGroups = grouped.map { (key: $0.key, albums: $0.value) }
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        case .genre:
            let grouped = Dictionary(grouping: filtered) { $0.genre ?? "Unknown" }
            cachedGroups = grouped.map { (key: $0.key, albums: $0.value) }
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        default:
            cachedGroups = []
        }
    }

    private var isRefreshing: Bool {
        library.scanState == .refreshing || library.scanState == .scanning
    }

    private var shouldGroup: Bool {
        sortOption == .genre || (sortOption == .artist && settings.groupByArtist)
    }

    var body: some View {
        // Manual navigation (no NavigationStack): a NavigationStack on macOS
        // routes its back button through the window toolbar, which can't
        // coexist with the custom top bar. The detail for the top of
        // `router.collectionPath` is shown in place; `DetailBackButton` pops it.
        Group {
            if let top = router.collectionPath.last {
                detailView(for: top)
                    .transition(.opacity)
            } else {
                rootContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: router.collectionPath)
        .onAppear { recomputeVisible() }
        .onChange(of: library.tracks) { _, _ in recomputeVisible() }
        .onChange(of: searchText) { _, _ in recomputeVisible() }
        .onChange(of: sortOption) { _, _ in recomputeVisible() }
        .sheet(item: $editingAlbum) { album in
            AlbumMetadataEditorView(album: album)
                .environment(library)
        }
    }

    private var rootContent: some View {
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
                            albumList(cachedFiltered)
                        } else {
                            albumGrid(cachedFiltered)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.bottom, 100)
                }
                .task { canAnimateEntrances = true }
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
    }

    @ViewBuilder
    private func detailView(for value: String) -> some View {
        if let artistKey = NavigationRoute.artistKey(from: value) {
            ArtistDetailView(artistKey: artistKey)
        } else {
            AlbumDetailView(albumID: value)
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
            let n = cachedFiltered.count
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
            ForEach(cachedGroups, id: \.key) { group in
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
                Button { router.collectionPath.append(album.id) } label: {
                    AlbumCardView(album: album)
                }
                .buttonStyle(.plain)
                .flContextMenu { albumContextMenu(album) }
                .riseFadeIn(index: index, animated: album.id, animatedIDs: animatedAlbumIDs, enabled: canAnimateEntrances)
            }
        }
    }

    // MARK: - Album List

    private func albumList(_ albums: [Album]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                Button { router.collectionPath.append(album.id) } label: {
                    AlbumRowView(album: album)
                }
                .buttonStyle(.plain)
                .flContextMenu { albumContextMenu(album) }
                .riseFadeIn(index: index, animated: album.id, animatedIDs: animatedAlbumIDs, enabled: canAnimateEntrances)
            }
        }
    }

    private func albumContextMenu(_ album: Album) -> [FLContextMenuItem] {
        var items = playbackContextMenuItems(for: album.tracks, player: player)
        items.append(.divider)
        items.append(.button("Edit...", systemImage: "pencil") { editingAlbum = album })
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
