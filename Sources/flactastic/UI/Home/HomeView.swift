import SwiftUI

/// The library home / dashboard screen. Section order mirrors the design with
/// one change: the fidelity panel ("Fidelidex") is moved to the bottom. Sections
/// that depend on listening history are hidden until that history exists.
struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(ListeningStore.self) private var listening
    @Environment(PlayerState.self) private var player
    @Environment(NavigationRouter.self) private var router
    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(PlaylistAddCoordinator.self) private var playlistAddCoordinator

    /// Album lookup by `Album.id`, so history items (which store only the album
    /// key) can resolve back to real albums for artwork and playback.
    private var albumsByID: [String: Album] {
        Dictionary(library.albums.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                hero
                recentlyPlayedSection
                listeningStatsSection
                topAlbumsSection
                FidelidexView()
            }
            .padding(.horizontal, 36)
            .padding(.top, 44)
            .padding(.bottom, 120)   // clear the floating player bar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.textTertiary)
            Text("Welcome to your library.")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 14)
            heroSubtitle.padding(.top, 16)
        }
    }

    private var heroSubtitle: some View {
        let albumCount = library.albums.count
        let hours = Int((library.tracks.compactMap(\.duration).reduce(0, +) / 3600).rounded())
        return HStack(spacing: 6) {
            Text("\(albumCount.formatted()) albums")
            Text("·")
            Text("\(hours.formatted()) hours of music")
            Text("·")
            Text("Hi-Fi quality").foregroundStyle(Theme.qualityLossless)
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.textTertiary)
    }

    // MARK: - Recently Played

    @ViewBuilder
    private var recentlyPlayedSection: some View {
        let items = listening.recentlyPlayed(limit: 12)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Recently Played")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(items) { item in
                            recentTile(item)
                        }
                    }
                }
            }
        }
    }

    private func recentTile(_ item: RecentItem) -> some View {
        let album = item.albumID.flatMap { albumsByID[$0] }
        let artist = ArtistResolver.displayString(album?.artist)
            ?? ArtistResolver.displayString(item.subtitle)
            ?? item.subtitle
        return Button {
            if let album { router.navigateToAlbum(id: album.id) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ArtworkView(data: album?.artwork, size: 148)
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(artist)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 148, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(album == nil)
        .flContextMenu { album.map(albumContextMenu) ?? [] }
    }

    /// Custom context menu for an album tile/row on the home page — mirrors the
    /// Collection's album menu (playback, View Album, Add to Playlist, artist
    /// actions).
    private func albumContextMenu(_ album: Album) -> [FLContextMenuItem] {
        var items: [FLContextMenuItem] = [
            .button("Play Album", systemImage: "play.fill") {
                player.startFreshQueue(album.tracks, source: album.name)
                player.engine.play()
            }
        ]
        items.append(contentsOf: playbackContextMenuItems(for: album.tracks, player: player))
        items.append(.divider)
        items.append(.button("View Album", systemImage: "square.grid.2x2") {
            router.navigateToAlbum(id: album.id)
        })
        items.append(addToPlaylistMenuItem(tracks: album.tracks))
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

    /// "Add to Playlist" submenu for a set of tracks, matching the pattern used
    /// in AlbumDetailView / AllTracksView.
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

    // MARK: - Listening Stats

    @ViewBuilder
    private var listeningStatsSection: some View {
        // The whole block is gated on having any history — without plays there
        // is nothing meaningful to show besides the always-available album count
        // already in the hero.
        if listening.hasHistory {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    sectionHeader("Your Listening Stats")
                    Spacer()
                    Text("All time").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
                statCards
                HStack(alignment: .top, spacing: 12) {
                    WeeklyListeningChart(
                        minutes: listening.weeklyMinutes(),
                        labels: listening.weeklyDayLabels()
                    )
                    topArtistsCard
                }
            }
        }
    }

    private var statCards: some View {
        let hours = Int((listening.totalSecondsListened / 3600).rounded())
        var cards: [HomeStatCard] = [
            HomeStatCard(icon: "clock", value: "\(hours)h", label: "Hours Listened", accent: true),
            HomeStatCard(icon: "music.note", value: listening.tracksPlayedCount.abbreviated(), label: "Tracks Played"),
            HomeStatCard(icon: "rectangle.stack", value: listening.albumsPlayedCount.formatted(), label: "Albums"),
            HomeStatCard(icon: "headphones", value: listening.sessionCount.formatted(), label: "Sessions"),
        ]
        if let genre = listening.topGenre {
            cards.append(HomeStatCard(icon: "star", value: genre.name, label: "Top Genre",
                                      detail: "\(Int((genre.share * 100).rounded()))% of plays"))
        }
        let streak = listening.currentStreakDays
        if streak > 0 {
            cards.append(HomeStatCard(icon: "chart.line.uptrend.xyaxis",
                                      value: "\(streak) day\(streak == 1 ? "" : "s")",
                                      label: "Current Streak", accent: true))
        }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
            ForEach(cards) { $0 }
        }
    }

    private var topArtistsCard: some View {
        let artists = listening.topArtists(limit: 5)
        let maxPlays = artists.first?.plays ?? 1
        return VStack(alignment: .leading, spacing: 16) {
            Text("Top Artists").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            if artists.isEmpty {
                Text("Not enough plays yet").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(artists.enumerated()), id: \.element.id) { idx, artist in
                        HStack(spacing: 11) {
                            Text("\(idx + 1)")
                                .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                                .monospacedDigit().frame(width: 12, alignment: .trailing)
                            VStack(spacing: 6) {
                                HStack {
                                    Text(ArtistResolver.displayString(artist.name) ?? artist.name)
                                        .font(.system(size: 11))
                                        .foregroundStyle(idx == 0 ? Theme.textPrimary : Theme.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(artist.plays.formatted())
                                        .font(.system(size: 10)).foregroundStyle(Theme.textTertiary).monospacedDigit()
                                }
                                ProgressBar(
                                    fraction: Double(artist.plays) / Double(maxPlays),
                                    tint: idx == 0 ? Theme.qualityLossless : Theme.textPrimary.opacity(0.45)
                                )
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 240, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.divider))
    }

    // MARK: - Top Albums This Week

    @ViewBuilder
    private var topAlbumsSection: some View {
        let albums = listening.topAlbumsThisWeek(limit: 6)
        if !albums.isEmpty {
            let maxPlays = albums.first?.plays ?? 1
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Top Albums This Week")
                VStack(spacing: 1) {
                    ForEach(Array(albums.enumerated()), id: \.element.id) { idx, rank in
                        topAlbumRow(idx: idx, rank: rank, maxPlays: maxPlays)
                    }
                }
                .background(Theme.divider, in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.divider))
            }
        }
    }

    private func topAlbumRow(idx: Int, rank: AlbumRank, maxPlays: Int) -> some View {
        let album = albumsByID[rank.albumID]
        let artist = ArtistResolver.displayString(album?.artist)
            ?? ArtistResolver.displayString(rank.artist)
            ?? rank.artist
        return Button {
            if let album {
                player.startFreshQueue(album.tracks, source: album.name)
                player.engine.play()
            }
        } label: {
            HStack(spacing: 14) {
                Text("\(idx + 1)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(idx == 0 ? Theme.qualityLossless : Theme.textTertiary)
                    .monospacedDigit().frame(width: 16, alignment: .trailing)
                ArtworkView(data: album?.artwork, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(rank.album).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(artist).font(.system(size: 10)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                Spacer()
                ProgressBar(
                    fraction: Double(rank.plays) / Double(maxPlays),
                    tint: idx == 0 ? Theme.qualityLossless : Theme.textPrimary.opacity(0.35)
                )
                .frame(width: 150)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(rank.plays) plays").font(.system(size: 11)).foregroundStyle(Theme.textSecondary).monospacedDigit()
                    Text("\(Int(rank.minutes.rounded())) min").font(.system(size: 10)).foregroundStyle(Theme.textTertiary).monospacedDigit()
                }
                .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Theme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .flContextMenu { album.map(albumContextMenu) ?? [] }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(Theme.textSecondary)
    }
}

// MARK: - Stat card

struct HomeStatCard: View, Identifiable {
    let id = UUID()
    let icon: String
    let value: String
    let label: String
    var detail: String? = nil
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(accent ? Theme.qualityLossless : Theme.textTertiary)
                .frame(width: 30, height: 30)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.divider))
                .padding(.bottom, 12)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 9)).tracking(1)
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 4)
            if let detail {
                Text(detail).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7).padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.divider))
    }
}

// MARK: - Weekly chart

struct WeeklyListeningChart: View {
    let minutes: [Double]
    let labels: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weekly Listening").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Minutes per day").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Text("This week").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            }
            chart.frame(height: 132)
            HStack {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.divider))
    }

    private var chart: some View {
        GeometryReader { geo in
            let maxV = max(minutes.max() ?? 1, 1)
            let pts = points(in: geo.size, maxValue: maxV)
            ZStack {
                if pts.count > 1 {
                    // Filled area
                    areaPath(pts, height: geo.size.height)
                        .fill(LinearGradient(
                            colors: [Theme.qualityLossless.opacity(0.26), Theme.qualityLossless.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                    // Line
                    linePath(pts)
                        .stroke(Theme.qualityLossless, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize, maxValue: Double) -> [CGPoint] {
        guard !minutes.isEmpty else { return [] }
        let stepX = minutes.count > 1 ? size.width / CGFloat(minutes.count - 1) : size.width
        return minutes.enumerated().map { idx, value in
            let x = CGFloat(idx) * stepX
            let y = size.height - CGFloat(value / maxValue) * size.height
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var p = Path()
        p.move(to: pts[0])
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        return p
    }

    private func areaPath(_ pts: [CGPoint], height: CGFloat) -> Path {
        var p = linePath(pts)
        p.addLine(to: CGPoint(x: pts.last!.x, y: height))
        p.addLine(to: CGPoint(x: pts.first!.x, y: height))
        p.closeSubpath()
        return p
    }
}

// MARK: - Number formatting

private extension Int {
    /// Compact form for large counts ("12.4k"), plain otherwise.
    func abbreviated() -> String {
        if self >= 1000 {
            let thousands = Double(self) / 1000.0
            return String(format: "%.1fk", thousands)
        }
        return formatted()
    }
}
