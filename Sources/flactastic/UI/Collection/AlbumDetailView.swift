import SwiftUI

struct AlbumDetailView: View {
    let albumID: String

    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player
    @Environment(PlaylistStore.self) private var playlistStore

    private var album: Album? {
        library.albums.first { $0.id == albumID }
    }

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
                        player.engine.setQueue(tracks, startAt: index)
                        player.engine.play()
                    }
                    .contextMenu {
                        addToPlaylistMenu(track: track)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(
                        player.currentTrack?.id == track.id
                            ? Theme.surfaceElevated
                            : Color.clear
                    )

                if index < tracks.count - 1 {
                    Divider().foregroundStyle(Theme.divider)
                }
            }
        }
    }

    @ViewBuilder
    private func addToPlaylistMenu(track: Track) -> some View {
        if playlistStore.playlists.isEmpty {
            Text("No playlists yet")
        } else {
            Menu("Add to Playlist") {
                ForEach(playlistStore.playlists) { playlist in
                    Button(playlist.name) {
                        playlistStore.addTracks([track], to: playlist.id, relativeTo: library.rootURL)
                    }
                }
            }
        }
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
        player.engine.setQueue(tracks, startAt: 0)
        player.engine.play()
    }
}
