import SwiftUI

// MARK: - debugMode

private struct DebugModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the Lucida debug window is open (View → Enable Debugging).
    /// Used to gate developer-only UI such as the VPN notice reset toggle in Settings.
    var debugMode: Bool {
        get { self[DebugModeKey.self] }
        set { self[DebugModeKey.self] = newValue }
    }
}
