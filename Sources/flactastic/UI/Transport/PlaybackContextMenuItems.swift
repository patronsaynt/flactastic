import SwiftUI

/// The shared "Play Next" / "Add to Queue" menu items, used from track rows,
/// album cards/rows, and playlist cards/rows. Returns raw items (no enclosing
/// `contextMenu` wrapper) so call sites can combine them with their own
/// per-context actions (e.g. "Add to Playlist", "Remove from Playlist").
@MainActor
@ViewBuilder
func playbackContextMenuItems(for tracks: [Track], player: PlayerState) -> some View {
    if !tracks.isEmpty {
        Button {
            player.playNext(tracks)
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            player.addToQueue(tracks)
        } label: {
            Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
        }
    }
}
