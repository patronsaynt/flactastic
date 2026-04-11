import SwiftUI

struct PlaylistSidebarSection: View {
    @Binding var selection: SidebarSelection?

    @Environment(PlaylistStore.self) private var playlistStore
    @Environment(LibraryStore.self) private var library

    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            playlistRows
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack {
            Text("Playlists")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)

            Spacer()

            Button {
                let playlist = playlistStore.createPlaylist(name: "New Playlist")
                selection = .playlist(playlist.id)
                // Start renaming immediately
                renamingID = playlist.id
                renameText = playlist.name
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - Rows

    private var playlistRows: some View {
        ForEach(playlistStore.playlists) { playlist in
            playlistRow(playlist)
        }
    }

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        let isSelected = selection == .playlist(playlist.id)
        let trackCount = playlistStore.resolvedTracks(for: playlist, in: library).count

        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "music.note.list")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)

            if renamingID == playlist.id {
                TextField("Playlist name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textPrimary)
                    .onSubmit {
                        commitRename(for: playlist.id)
                    }
            } else {
                Text(playlist.name)
                    .font(Theme.Font.body)
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(trackCount)")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(isSelected ? Theme.surfaceElevated : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = .playlist(playlist.id)
        }
        .contextMenu {
            Button("Rename") {
                renameText = playlist.name
                renamingID = playlist.id
            }
            Divider()
            Button("Delete", role: .destructive) {
                if selection == .playlist(playlist.id) {
                    selection = .library
                }
                playlistStore.deletePlaylist(id: playlist.id)
            }
        }
    }

    // MARK: - Actions

    private func commitRename(for id: UUID) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            playlistStore.renamePlaylist(id: id, name: trimmed)
        }
        renamingID = nil
    }
}
