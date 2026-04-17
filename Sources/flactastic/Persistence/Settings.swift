import Foundation
import Observation

@Observable
@MainActor
final class Settings {
    var lastRootPath: String? {
        didSet { UserDefaults.standard.set(lastRootPath, forKey: "flactastic.lastRootPath") }
    }

    var volume: Float {
        didSet { UserDefaults.standard.set(volume, forKey: "flactastic.volume") }
    }

    var useLightMode: Bool {
        didSet { UserDefaults.standard.set(useLightMode, forKey: "flactastic.useLightMode") }
    }

    var useListLayout: Bool {
        didSet { UserDefaults.standard.set(useListLayout, forKey: "flactastic.useListLayout") }
    }

    /// UI scale factor. 1.0 = default. Clamped to 0.9...1.35 in the view layer.
    var uiScale: Double {
        didSet { UserDefaults.standard.set(uiScale, forKey: "flactastic.uiScale") }
    }

    /// Whether the menu bar mini-player is shown. When false, the `MenuBarExtra`
    /// scene is omitted entirely so no icon appears in the system menu bar.
    var showMenuBarPlayer: Bool {
        didSet { UserDefaults.standard.set(showMenuBarPlayer, forKey: "flactastic.showMenuBarPlayer") }
    }

    var roundedArtwork: Bool {
        didSet { UserDefaults.standard.set(roundedArtwork, forKey: "flactastic.roundedArtwork") }
    }

    init() {
        lastRootPath = UserDefaults.standard.string(forKey: "flactastic.lastRootPath")
        let stored = UserDefaults.standard.object(forKey: "flactastic.volume")
        volume = (stored as? Float) ?? 0.75
        useLightMode = UserDefaults.standard.bool(forKey: "flactastic.useLightMode")
        useListLayout = UserDefaults.standard.bool(forKey: "flactastic.useListLayout")
        let storedScale = UserDefaults.standard.object(forKey: "flactastic.uiScale")
        uiScale = (storedScale as? Double) ?? 1.0
        let storedMBP = UserDefaults.standard.object(forKey: "flactastic.showMenuBarPlayer")
        showMenuBarPlayer = (storedMBP as? Bool) ?? true
        let storedRA = UserDefaults.standard.object(forKey: "flactastic.roundedArtwork")
        roundedArtwork = (storedRA as? Bool) ?? true
    }
}
