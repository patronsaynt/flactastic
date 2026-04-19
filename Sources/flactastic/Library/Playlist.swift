import Foundation

/// A single entry in a playlist, carrying its own stable UUID so SwiftUI can
/// track identity across reorders without relying on array offset.
struct PlaylistEntry: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    var relativePath: String

    init(id: UUID = UUID(), relativePath: String) {
        self.id = id
        self.relativePath = relativePath
    }
}

struct Playlist: Identifiable, Sendable, Hashable {
    static let descriptionMaxLength = 200

    let id: UUID
    var name: String
    var entries: [PlaylistEntry]
    var dateCreated: Date
    var customArtwork: Data?
    var description: String?

    init(
        id: UUID = UUID(),
        name: String,
        entries: [PlaylistEntry] = [],
        dateCreated: Date = Date(),
        customArtwork: Data? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.dateCreated = dateCreated
        self.customArtwork = customArtwork
        self.description = description
    }
}

// MARK: - Codable with migration from old trackPaths format

extension Playlist: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, entries, trackPaths, dateCreated, customArtwork, description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        customArtwork = try container.decodeIfPresent(Data.self, forKey: .customArtwork)
        description = try container.decodeIfPresent(String.self, forKey: .description)

        // Try new format first, fall back to old trackPaths array.
        if let entries = try? container.decode([PlaylistEntry].self, forKey: .entries) {
            self.entries = entries
        } else if let paths = try? container.decode([String].self, forKey: .trackPaths) {
            self.entries = paths.map { PlaylistEntry(relativePath: $0) }
        } else {
            self.entries = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(entries, forKey: .entries)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encodeIfPresent(customArtwork, forKey: .customArtwork)
        try container.encodeIfPresent(description, forKey: .description)
    }
}
