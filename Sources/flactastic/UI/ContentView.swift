import SwiftUI

struct ContentView: View {
    @Environment(PlayerState.self) private var player
    @Environment(LibraryStore.self) private var library

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            NowPlayingView()
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        .safeAreaInset(edge: .bottom) {
            TransportControlsView()
        }
        .background(Theme.background)
    }
}

private struct SidebarView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerState.self) private var player
    @Environment(Settings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            LibraryHeaderView()
            Divider().foregroundStyle(Theme.divider)
            TrackListView()
        }
        .background(Theme.surface)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FolderPickerButton()
            }
        }
    }
}
