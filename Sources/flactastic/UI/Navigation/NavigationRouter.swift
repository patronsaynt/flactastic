import Foundation
import Observation

@Observable
@MainActor
final class NavigationRouter {
    var selectedTab: AppTab = .collection
    var collectionPath: [String] = []

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
}
