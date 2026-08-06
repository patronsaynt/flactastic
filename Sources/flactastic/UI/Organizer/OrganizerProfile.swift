import Foundation

/// Field used to bucket tracks at one level of the folder hierarchy.
enum GroupingField: String, Codable, CaseIterable, Identifiable, Hashable {
    case albumArtist
    case artist
    case album
    case genre
    case year
    case decade
    case format
    case firstLetterOfArtist

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .albumArtist: return "Album Artist"
        case .artist: return "Artist"
        case .album: return "Album"
        case .genre: return "Genre"
        case .year: return "Year"
        case .decade: return "Decade"
        case .format: return "Format"
        case .firstLetterOfArtist: return "Artist Initial"
        }
    }

    /// The default folder-name template for a level grouped by this field.
    var defaultTemplate: String {
        switch self {
        case .albumArtist: return "{albumArtist}"
        case .artist: return "{artist}"
        case .album: return "{album}"
        case .genre: return "{genre}"
        case .year: return "{year}"
        case .decade: return "{decade}s"
        case .format: return "{format}"
        case .firstLetterOfArtist: return "{artistInitial}"
        }
    }
}

/// One level in the folder hierarchy. `nameTemplate` renders the folder name —
/// tracks that render to the same name share a folder. `name` is the user's own
/// label for the level (shown in the builder, and used as the fallback folder
/// name when a template renders to nothing). `groupBy` seeds the defaults for a
/// newly-added level and is retained so profiles saved by older builds decode.
struct HierarchyLevel: Codable, Identifiable, Hashable {
    var id: UUID
    var groupBy: GroupingField
    var name: String
    var nameTemplate: String

    init(id: UUID = UUID(), groupBy: GroupingField, name: String? = nil, nameTemplate: String? = nil) {
        self.id = id
        self.groupBy = groupBy
        self.name = name ?? groupBy.displayName
        self.nameTemplate = nameTemplate ?? groupBy.defaultTemplate
    }

    enum CodingKeys: String, CodingKey {
        case id, groupBy, name, nameTemplate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let field = try c.decode(GroupingField.self, forKey: .groupBy)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.groupBy = field
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? field.displayName
        self.nameTemplate = try c.decode(String.self, forKey: .nameTemplate)
    }

    /// Non-empty label to show in the UI and to fall back to when a template
    /// renders to an empty string.
    var displayLabel: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? groupBy.displayName : trimmed
    }
}

/// A user-saved configuration for the Organizer.
struct OrganizerProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var levels: [HierarchyLevel]
    var fileTemplate: String
    /// When true, multi-artist values like "A & B", "A; B", "A feat. B" are
    /// reduced to just the first/primary artist for both folder bucketing and
    /// template rendering. Keeps collaborations filed under the lead artist
    /// instead of creating a separate folder per combination.
    var usePrimaryArtistOnly: Bool
    /// When true, source directories that become empty after a move are
    /// deleted bottom-up (stopping at the source root). When false, empty
    /// shells are left in place for the user to clean up manually.
    var deleteEmptyOriginals: Bool

    init(
        id: UUID = UUID(),
        name: String,
        levels: [HierarchyLevel],
        fileTemplate: String = "{track} - {title}",
        usePrimaryArtistOnly: Bool = true,
        deleteEmptyOriginals: Bool = true
    ) {
        self.id = id
        self.name = name
        self.levels = levels
        self.fileTemplate = fileTemplate
        self.usePrimaryArtistOnly = usePrimaryArtistOnly
        self.deleteEmptyOriginals = deleteEmptyOriginals
    }

    enum CodingKeys: String, CodingKey {
        case id, name, levels, fileTemplate, usePrimaryArtistOnly, deleteEmptyOriginals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.levels = try c.decode([HierarchyLevel].self, forKey: .levels)
        self.fileTemplate = try c.decode(String.self, forKey: .fileTemplate)
        self.usePrimaryArtistOnly = try c.decodeIfPresent(Bool.self, forKey: .usePrimaryArtistOnly) ?? true
        self.deleteEmptyOriginals = try c.decodeIfPresent(Bool.self, forKey: .deleteEmptyOriginals) ?? true
    }

    /// Level appended when the user taps "Add level" in the builder.
    static func newLevel() -> HierarchyLevel {
        HierarchyLevel(groupBy: .genre, name: "New level", nameTemplate: "{genre}")
    }

    static let `default` = OrganizerProfile(
        name: "Artist / Album",
        levels: [
            HierarchyLevel(groupBy: .albumArtist, name: "Album Artist"),
            HierarchyLevel(groupBy: .album, name: "Album", nameTemplate: "{album} ({year})")
        ],
        fileTemplate: "{track} - {title}"
    )

    static let presets: [OrganizerProfile] = [
        .default,
        OrganizerProfile(
            name: "Genre / Artist / Album",
            levels: [
                HierarchyLevel(groupBy: .genre, name: "Genre"),
                HierarchyLevel(groupBy: .albumArtist, name: "Album Artist"),
                HierarchyLevel(groupBy: .album, name: "Album")
            ]
        ),
        OrganizerProfile(
            name: "Year / Album",
            levels: [
                HierarchyLevel(groupBy: .year, name: "Year"),
                HierarchyLevel(groupBy: .album, name: "Album", nameTemplate: "{albumArtist} - {album}")
            ]
        )
    ]
}
