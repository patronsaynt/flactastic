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

/// One level in the folder hierarchy. Tracks are bucketed by `groupBy`, and each
/// bucket's folder name is rendered from `nameTemplate`.
struct HierarchyLevel: Codable, Identifiable, Hashable {
    var id: UUID
    var groupBy: GroupingField
    var nameTemplate: String

    init(id: UUID = UUID(), groupBy: GroupingField, nameTemplate: String? = nil) {
        self.id = id
        self.groupBy = groupBy
        self.nameTemplate = nameTemplate ?? groupBy.defaultTemplate
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

    static let `default` = OrganizerProfile(
        name: "Artist / Album",
        levels: [
            HierarchyLevel(groupBy: .albumArtist),
            HierarchyLevel(groupBy: .album, nameTemplate: "{album} ({year})")
        ],
        fileTemplate: "{track} - {title}"
    )

    static let presets: [OrganizerProfile] = [
        .default,
        OrganizerProfile(
            name: "Genre / Artist / Album",
            levels: [
                HierarchyLevel(groupBy: .genre),
                HierarchyLevel(groupBy: .albumArtist),
                HierarchyLevel(groupBy: .album)
            ]
        ),
        OrganizerProfile(
            name: "Year / Album",
            levels: [
                HierarchyLevel(groupBy: .year),
                HierarchyLevel(groupBy: .album, nameTemplate: "{albumArtist} - {album}")
            ]
        )
    ]
}
