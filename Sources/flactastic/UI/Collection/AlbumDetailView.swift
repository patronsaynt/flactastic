import SwiftUI

struct AlbumDetailView: View {
    let albumID: String

    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player
    @Environment(PlaylistStore.self) private var playlistStore

    /// Track IDs we've observed belonging to this album. Used as a fallback
    /// for resolving the album after a metadata edit renames the album/artist
    /// (which changes `Album.id` since that id is derived from artist+name).
    @State private var knownTrackIDs: Set<UUID> = []

    private var album: Album? {
        if let exact = library.albums.first(where: { $0.id == albumID }) {
            return exact
        }
        guard !knownTrackIDs.isEmpty else { return nil }
        return library.albums.first { candidate in
            candidate.tracks.contains { knownTrackIDs.contains($0.id) }
        }
    }

    @State private var isEditingAlbum = false
    @State private var editingTrack: Track? = nil

    var body: some View {
        if let album {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    albumHeader(album)
                    trackList(album.tracks)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Theme.background)
            .navigationTitle(album.name)
            .sheet(isPresented: $isEditingAlbum) {
                AlbumMetadataEditorView(album: album)
                    .environment(library)
            }
            .sheet(item: $editingTrack) { track in
                TrackMetadataEditorView(track: track)
                    .environment(library)
            }
            .onAppear {
                knownTrackIDs = Set(album.tracks.map(\.id))
            }
            .onChange(of: album.tracks.map(\.id)) { _, ids in
                knownTrackIDs = Set(ids)
            }
        } else {
            Text("Album not found")
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
    }

    // MARK: - Album Header

    private func albumHeader(_ album: Album) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            ArtworkView(data: album.artwork, size: 200)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(album.name)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.textPrimary)

                if let artist = album.artist {
                    Text(artist)
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: Theme.Spacing.md) {
                    if let year = album.year {
                        metadataTag("\(year)")
                    }
                    if let genre = album.genre {
                        metadataTag(genre)
                    }
                    metadataTag("\(album.trackCount) tracks")
                    metadataTag(FormatUtils.formatDuration(album.totalDuration))
                }

                Spacer()

                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        playAlbum(album, shuffle: false)
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "play.fill")
                            Text("Play All")
                        }
                    }
                    .buttonStyle(PillButtonStyle(isPrimary: true))

                    Button {
                        playAlbum(album, shuffle: true)
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "shuffle")
                            Text("Shuffle")
                        }
                    }
                    .buttonStyle(PillButtonStyle())

                    Button {
                        isEditingAlbum = true
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "pencil")
                            Text("Edit")
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }
        }
        .frame(height: 200)
    }

    // MARK: - Track List

    private func trackList(_ tracks: [Track]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track, isPlaying: player.currentTrack?.id == track.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        player.startFreshQueue(tracks, startAt: index, source: album?.name)
                        player.engine.play()
                    }
                    .flContextMenu {
                        playbackContextMenuItems(for: [track], player: player)
                        FLContextMenuItem.divider
                        FLContextMenuItem.button("Edit...") { editingTrack = track }
                        FLContextMenuItem.divider
                        addToPlaylistMenuItem(track: track)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(
                        player.currentTrack?.id == track.id
                            ? Theme.surfaceElevated
                            : Color.clear
                    )
                    .riseFadeIn(index: index)

                if index < tracks.count - 1 {
                    Divider().foregroundStyle(Theme.divider)
                }
            }
        }
    }

    private func addToPlaylistMenuItem(track: Track) -> FLContextMenuItem {
        if playlistStore.playlists.isEmpty {
            return .label("No playlists yet")
        }
        let children: [FLContextMenuItem] = playlistStore.playlists.map { playlist in
            .button(playlist.name) {
                playlistStore.addTracks([track], to: playlist.id, relativeTo: library.rootURL)
            }
        }
        return .submenu("Add to Playlist", systemImage: "plus.square.on.square", items: children)
    }

    private func metadataTag(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Theme.surfaceElevated)
            )
    }

    private func playAlbum(_ album: Album, shuffle: Bool) {
        var tracks = album.tracks
        if shuffle {
            player.setOriginalQueue(album.tracks)
            tracks.shuffle()
            player.isShuffleEnabled = true
        } else {
            player.isShuffleEnabled = false
        }
        player.startFreshQueue(tracks, startAt: 0, source: album.name)
        player.engine.play()
    }
}
