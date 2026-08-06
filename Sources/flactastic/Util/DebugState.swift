import Observation

/// Ephemeral (non-persisted) developer-tool state, backing the Debug tab in
/// Settings. Always starts OFF at launch, even if left on in a previous
/// session — these are diagnostic aids, not user preferences.
@Observable
@MainActor
final class DebugState {
    var lucidaDebugEnabled = false
}
