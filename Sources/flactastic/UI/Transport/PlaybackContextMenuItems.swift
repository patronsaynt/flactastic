import SwiftUI

/// The shared "Play Next" / "Add to Queue" items for the custom context menu,
/// used from track rows, album cards/rows, and playlist cards/rows. Returns
/// raw items so callers can splice in their own per-context actions (e.g.
/// "Add to Playlist", "Remove from Playlist").
@MainActor
func playbackContextMenuItems(for tracks: [Track], player: PlayerState) -> [FLContextMenuItem] {
    guard !tracks.isEmpty else { return [] }
    return [
        .button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            player.playNext(tracks)
        },
        .button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") {
            player.addToQueue(tracks)
        }
    ]
}
