import Foundation
import Observation

/// Drives presentation of the three import sheets (track, album, playlist)
/// from the `Collection` menu in the app menu bar. `ContentView` observes
/// `active` and presents the matching sheet; menu commands call `begin(_:)`.
@Observable
@MainActor
final class ImportCoordinator {
    enum Mode: Int, Identifiable, Hashable {
        case track
        case album
        case playlist

        var id: Int { rawValue }
    }

    var active: Mode? = nil

    func begin(_ mode: Mode) { active = mode }
    func dismiss() { active = nil }
}
