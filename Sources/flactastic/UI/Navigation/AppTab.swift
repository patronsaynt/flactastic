import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case collection = "Collection"
    case playlists = "Playlists"
    case download = "Download"
    case organizer = "Organizer"
    case visualizer = "Visualizer"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home:       return "music.note.house"
        case .collection: return "music.note.list"
        case .playlists:  return "list.bullet.rectangle"
        case .download:   return "arrow.down.circle"
        case .organizer:  return "slider.horizontal.3"
        case .visualizer: return "waveform"
        }
    }

    /// Library tabs are separated from tool tabs by a divider in the nav bar.
    var isLibraryTab: Bool {
        switch self {
        case .home, .collection, .playlists:     return true
        case .download, .organizer, .visualizer: return false
        }
    }
}
