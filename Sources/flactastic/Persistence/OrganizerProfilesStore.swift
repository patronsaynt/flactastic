import Foundation
import Observation

/// Persists organizer profiles and the user's currently-selected profile. Stores
/// JSON in UserDefaults so the existing Settings pattern is matched without
/// pulling in a database. Always guarantees at least one profile exists — on
/// first launch it seeds the default preset.
@Observable
@MainActor
final class OrganizerProfilesStore {
    private static let profilesKey = "flactastic.organizer.profiles"
    private static let selectedKey = "flactastic.organizer.selectedProfileID"

    var profiles: [OrganizerProfile] {
        didSet { persistProfiles() }
    }

    var selectedID: UUID {
        didSet { UserDefaults.standard.set(selectedID.uuidString, forKey: Self.selectedKey) }
    }

    var selected: OrganizerProfile {
        get { profiles.first { $0.id == selectedID } ?? profiles[0] }
        set {
            guard let i = profiles.firstIndex(where: { $0.id == newValue.id }) else { return }
            profiles[i] = newValue
        }
    }

    init() {
        let decoded: [OrganizerProfile]
        if let data = UserDefaults.standard.data(forKey: Self.profilesKey),
           let parsed = try? JSONDecoder().decode([OrganizerProfile].self, from: data),
           !parsed.isEmpty {
            decoded = parsed
        } else {
            decoded = [OrganizerProfile.default]
        }
        self.profiles = decoded

        if let raw = UserDefaults.standard.string(forKey: Self.selectedKey),
           let uuid = UUID(uuidString: raw),
           decoded.contains(where: { $0.id == uuid }) {
            self.selectedID = uuid
        } else {
            self.selectedID = decoded[0].id
        }
    }

    func add(_ profile: OrganizerProfile) {
        profiles.append(profile)
        selectedID = profile.id
    }

    func duplicateSelected() {
        var copy = selected
        copy = OrganizerProfile(
            id: UUID(),
            name: "\(copy.name) Copy",
            levels: copy.levels.map { HierarchyLevel(id: UUID(), groupBy: $0.groupBy, nameTemplate: $0.nameTemplate) },
            fileTemplate: copy.fileTemplate
        )
        add(copy)
    }

    func removeSelected() {
        guard profiles.count > 1 else { return }
        guard let idx = profiles.firstIndex(where: { $0.id == selectedID }) else { return }
        profiles.remove(at: idx)
        selectedID = profiles[max(0, idx - 1)].id
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.profilesKey)
    }
}
