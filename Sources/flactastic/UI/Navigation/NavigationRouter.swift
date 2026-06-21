import Foundation
import Observation

@Observable
@MainActor
final class NavigationRouter {
    var selectedTab: AppTab = .home
    var collectionPath: [String] = []
    var artworkZoomData: Data? = nil

    func navigateToAlbum(id: String) {
        // Pop any current album, switch tabs, then push the new one on the
        // next runloop tick. Doing the push in one step caused the previously
        // open album to flash on screen first when the NavigationStack
        // reused its existing detail view for a same-length path swap.
        collectionPath = []
        selectedTab = .collection
        DispatchQueue.main.async {
            self.collectionPath = [id]
        }
    }

    /// Push an artist detail page. Encoded as `"artist:<canonicalKey>"` so it
    /// flows through the existing String-typed navigation stack alongside
    /// album IDs.
    func navigateToArtist(key: String) {
        selectedTab = .collection
        let value = NavigationRoute.artist(key: key)
        if collectionPath.last == value { return }
        collectionPath.append(value)
    }
}

/// Encoding helpers for the shared String-typed navigation stack. Album IDs
/// flow through as plain strings; artist pages use the `"artist:"` prefix.
enum NavigationRoute {
    static let artistPrefix = "artist:"

    static func artist(key: String) -> String { "\(artistPrefix)\(key)" }

    static func artistKey(from value: String) -> String? {
        guard value.hasPrefix(artistPrefix) else { return nil }
        return String(value.dropFirst(artistPrefix.count))
    }
}
