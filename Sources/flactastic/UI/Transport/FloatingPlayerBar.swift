import SwiftUI

struct FloatingPlayerBar: View {
    @Environment(PlayerState.self)       private var player
    @Environment(Settings.self)          private var settings
    @Environment(PlaylistStore.self)     private var playlistStore
    @Environment(LibraryStore.self)      private var library
    @Environment(NavigationRouter.self)  private var router

    @State private var showingNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        if player.currentTrack != nil {
            playerContent
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .fill(Theme.surface)
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                )
        }
    }

    private var playerContent: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                // Center: transport controls (centered to full bar width)
                transportControls

                // Left: track info / Right: queue toggle + volume pinned to edges
                HStack(spacing: Theme.Spacing.sm) {
                    trackInfo
                    Spacer(minLength: 0)
                    addToPlaylistButton
                    queueToggleButton
                    VolumeSliderView()
                }
            }

            SeekBarView()
        }
    }

    // MARK: - Track Info

    @ViewBuilder
    private var trackInfo: some View {
        if let track = player.currentTrack {
            HStack(spacing: Theme.Spacing.sm) {
                ArtworkView(data: track.artwork, size: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(Theme.Font.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let artist = ArtistResolver.displayString(track.artist) {
                        Text(artist)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 150, alignment: .leading)
            }
            .flContextMenu {
                FLContextMenuItem.button("View Album", systemImage: "square.grid.2x2") {
                    if let albumID = library.album(for: track)?.id {
                        router.navigateToAlbum(id: albumID)
                    }
                }
            }
        }
    }

    // MARK: - Add to Playlist

    private var addToPlaylistButton: some View {
        Button {
            FLContextMenuWindow.present(items: buildAddToPlaylistItems(), at: NSEvent.mouseLocation)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.textTertiary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 22, height: 22)
        .help("Add to playlist")
        .alert("New Playlist", isPresented: $showingNewPlaylistAlert) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Create") { createPlaylistAndAdd() }
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
        }
    }

    private func buildAddToPlaylistItems() -> [FLContextMenuItem] {
        var items: [FLContextMenuItem] = []
        if playlistStore.playlists.isEmpty {
            items.append(.label("No playlists yet"))
        } else {
            for playlist in playlistStore.playlists {
                items.append(.button(playlist.name) { addCurrentTrack(to: playlist.id) })
            }
            items.append(.divider)
        }
        items.append(.button("New Playlist…") { showingNewPlaylistAlert = true })
        return items
    }

    private func addCurrentTrack(to playlistID: UUID) {
        guard let track = player.currentTrack else { return }
        playlistStore.addTracks([track], to: playlistID, relativeTo: library.rootURL)
    }

    private func createPlaylistAndAdd() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { newPlaylistName = ""; return }
        let playlist = playlistStore.createPlaylist(name: name)
        addCurrentTrack(to: playlist.id)
        newPlaylistName = ""
    }

    // MARK: - Queue Toggle

    private var queueToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.28)) {
                player.isQueueVisible.toggle()
            }
        } label: {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(player.isQueueVisible ? Theme.accent : Theme.textTertiary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(player.isQueueVisible ? "Hide queue" : "Show queue")
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 11))
                    .foregroundStyle(player.isShuffleEnabled ? Theme.accent : Theme.textTertiary)
            }
            .buttonStyle(.plain)

            Button { player.engine.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { player.engine.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                switch player.repeatMode {
                case .off: player.repeatMode = .all
                case .all: player.repeatMode = .one
                case .one: player.repeatMode = .off
                }
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 11))
                    .foregroundStyle(player.repeatMode != .off ? Theme.accent : Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }
}
