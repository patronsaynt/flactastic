import Foundation

enum CollectionSortOption: String, CaseIterable, Identifiable {
    case album = "Album"
    case artist = "Artist"
    case year = "Year"
    case genre = "Genre"

    var id: String { rawValue }
}
