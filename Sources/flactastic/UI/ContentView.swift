import SwiftUI

enum SidebarSelection: Hashable {
    case library
    case playlist(UUID)
}

struct ContentView: View {
    @Environment(PlayerState.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(PlaylistStore.self) private var playlistStore

    @State private var selection: SidebarSelection? = .library

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            detailView
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        .safeAreaInset(edge: .bottom) {
            TransportControlsView()
        }
        .background(Theme.background)
        .onChange(of: library.scanState) { _, newState in
            if case .done = newState {
                playlistStore.reconcile(with: library)
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .library, .none:
            NowPlayingView()
        case .playlist:
            NowPlayingView()
        }
    }
}

private struct SidebarView: View {
    @Binding var selection: SidebarSelection?

    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player
    @Environment(Settings.self) private var settings
    @Environment(PlaylistStore.self) private var playlistStore

    var body: some View {
        VStack(spacing: 0) {
            LibraryHeaderView()
            Divider().foregroundStyle(Theme.divider)

            // Library row
            libraryRow

            Divider().foregroundStyle(Theme.divider)

            // Playlists section
            PlaylistSidebarSection(selection: $selection)

            Divider().foregroundStyle(Theme.divider)

            // Track list for current selection
            trackContent
        }
        .background(Theme.surface)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FolderPickerButton()
            }
        }
    }

    private var libraryRow: some View {
        let isSelected = selection == .library
        return HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "music.quarternote.3")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)

            Text("All Tracks")
                .font(Theme.Font.body)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)

            Spacer()

            Text("\(library.tracks.count)")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(isSelected ? Theme.surfaceElevated : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = .library
        }
    }

    @ViewBuilder
    private var trackContent: some View {
        switch selection {
        case .library, .none:
            TrackListView()
        case .playlist(let id):
            PlaylistDetailView(playlistID: id)
        }
    }
}
