import Foundation

struct Playlist: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var trackPaths: [String]   // relative paths from library root
    var dateCreated: Date

    init(id: UUID = UUID(), name: String, trackPaths: [String] = [], dateCreated: Date = Date()) {
        self.id = id
        self.name = name
        self.trackPaths = trackPaths
        self.dateCreated = dateCreated
    }
}
