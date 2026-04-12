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

    init() {
        lastRootPath = UserDefaults.standard.string(forKey: "flactastic.lastRootPath")
        let stored = UserDefaults.standard.object(forKey: "flactastic.volume")
        volume = (stored as? Float) ?? 0.75
        useLightMode = UserDefaults.standard.bool(forKey: "flactastic.useLightMode")
        useListLayout = UserDefaults.standard.bool(forKey: "flactastic.useListLayout")
    }
}
