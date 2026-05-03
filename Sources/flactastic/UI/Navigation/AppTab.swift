import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case collection = "Collection"
    case playlists = "Playlists"
    case download = "Download"
    case visualizer = "Visualizer"
    case organizer = "Organizer"

    var id: String { rawValue }
}
