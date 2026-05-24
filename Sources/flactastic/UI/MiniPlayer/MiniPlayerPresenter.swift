import Foundation
import Observation

/// Session-only state for the pop-out mini player. Lives in `FlactasticApp`'s
/// state so the same instance is in the environment of both the main window
/// and the mini-player window, letting either side flip `isVisible` (e.g. the
/// `FloatingPlayerBar` pop-out button, the Visualizer mode picker entry, or
/// the mini player's own close affordance).
///
/// `isPinned` controls whether the mini-player NSWindow sits at `.floating`
/// level (always above other apps). The window itself reads this via
/// `MiniPlayerView.onChange(of:)` and adjusts its `NSWindow.level`.
@Observable
@MainActor
final class MiniPlayerPresenter {
    /// True when the mini-player window should be open. Toggled from the
    /// `FloatingPlayerBar` icon and the Visualizer mode picker.
    var isVisible: Bool = false

    /// True when the mini-player should float above other apps.
    var isPinned: Bool = false
}
