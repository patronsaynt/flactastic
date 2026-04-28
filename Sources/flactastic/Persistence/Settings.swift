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

    var showArtworkShadow: Bool {
        didSet { UserDefaults.standard.set(showArtworkShadow, forKey: "flactastic.showArtworkShadow") }
    }

    var fadeAnimationsEnabled: Bool {
        didSet { UserDefaults.standard.set(fadeAnimationsEnabled, forKey: "flactastic.fadeAnimationsEnabled") }
    }

    var fadeAnimationDirection: FadeAnimationDirection {
        didSet { UserDefaults.standard.set(fadeAnimationDirection.rawValue, forKey: "flactastic.fadeAnimationDirection") }
    }

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "flactastic.hasCompletedOnboarding") }
    }

    var groupByArtist: Bool {
        didSet { UserDefaults.standard.set(groupByArtist, forKey: "flactastic.groupByArtist") }
    }

    var customGenres: [String] {
        didSet { UserDefaults.standard.set(customGenres, forKey: "flactastic.customGenres") }
    }

    /// When true, missing artist profile images are fetched from Deezer.
    /// User-supplied images always take priority regardless of this setting.
    var autoFetchArtistImages: Bool {
        didSet { UserDefaults.standard.set(autoFetchArtistImages, forKey: "flactastic.autoFetchArtistImages") }
    }

    var discordRichPresenceEnabled: Bool {
        didSet { UserDefaults.standard.set(discordRichPresenceEnabled, forKey: "flactastic.discordRichPresenceEnabled") }
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
        let storedShadow = UserDefaults.standard.object(forKey: "flactastic.showArtworkShadow")
        showArtworkShadow = (storedShadow as? Bool) ?? true
        let storedFade = UserDefaults.standard.object(forKey: "flactastic.fadeAnimationsEnabled")
        fadeAnimationsEnabled = (storedFade as? Bool) ?? true
        let storedDir = UserDefaults.standard.string(forKey: "flactastic.fadeAnimationDirection")
        fadeAnimationDirection = storedDir.flatMap(FadeAnimationDirection.init(rawValue:)) ?? .up
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "flactastic.hasCompletedOnboarding")
        groupByArtist = UserDefaults.standard.bool(forKey: "flactastic.groupByArtist")
        customGenres = UserDefaults.standard.stringArray(forKey: "flactastic.customGenres") ?? []
        let storedAutoFetch = UserDefaults.standard.object(forKey: "flactastic.autoFetchArtistImages")
        autoFetchArtistImages = (storedAutoFetch as? Bool) ?? true
        let storedDRP = UserDefaults.standard.object(forKey: "flactastic.discordRichPresenceEnabled")
        discordRichPresenceEnabled = (storedDRP as? Bool) ?? true
    }
}

enum FadeAnimationDirection: String, CaseIterable, Identifiable {
    case up
    case leftToRight
    case rightToLeft

    var id: String { rawValue }

    var label: String {
        switch self {
        case .up: return "Upward"
        case .leftToRight: return "Left to Right"
        case .rightToLeft: return "Right to Left"
        }
    }
}
