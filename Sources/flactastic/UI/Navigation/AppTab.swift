import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case collection = "Collection"
    case playlists = "Playlists"
    case visualizer = "Visualizer"

    var id: String { rawValue }
}
