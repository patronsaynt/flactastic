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

    /// Last-selected visualizer mode. Restored when the user opens the Visualizer tab.
    var visualizerMode: VisualizerMode {
        didSet { UserDefaults.standard.set(visualizerMode.rawValue, forKey: "flactastic.visualizerMode") }
    }

    /// When true, Big Picture mode shows a small fullscreen toggle in the top-right corner.
    var showBigPictureFullScreenToggle: Bool {
        didSet { UserDefaults.standard.set(showBigPictureFullScreenToggle, forKey: "flactastic.showBigPictureFullScreenToggle") }
    }

    /// When true, the Lyrics visualizer mode fetches lyrics from lrclib.net.
    /// Disable for offline / privacy-conscious use; cached entries still display.
    var lyricsLookupEnabled: Bool {
        didSet { UserDefaults.standard.set(lyricsLookupEnabled, forKey: "flactastic.lyricsLookupEnabled") }
    }

    /// When true, successfully-fetched lyrics are written into the LYRICS tag
    /// on the source audio file (cross-format: Xiph LYRICS / ID3v2 USLT /
    /// MP4 ©lyr). Off keeps user files untouched.
    var saveLyricsToFiles: Bool {
        didSet { UserDefaults.standard.set(saveLyricsToFiles, forKey: "flactastic.saveLyricsToFiles") }
    }

    var showVpnNotice: Bool {
        didSet { UserDefaults.standard.set(showVpnNotice, forKey: "flactastic.showVpnNotice") }
    }

    /// Spotify Web API app credentials (Client Credentials flow). When both are
    /// set, playlist rebuilds fetch the *complete* tracklist via the official
    /// API instead of Spotify's 100-track embed preview. Optional — the embed
    /// fallback works without them for playlists up to 100 tracks.
    var spotifyClientID: String {
        didSet { UserDefaults.standard.set(spotifyClientID, forKey: "flactastic.spotifyClientID") }
    }

    var spotifyClientSecret: String {
        didSet { UserDefaults.standard.set(spotifyClientSecret, forKey: "flactastic.spotifyClientSecret") }
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
        let storedVis = UserDefaults.standard.string(forKey: "flactastic.visualizerMode")
        visualizerMode = storedVis.flatMap(VisualizerMode.init(rawValue:)) ?? .albumArtLargeDetails
        let storedBPToggle = UserDefaults.standard.object(forKey: "flactastic.showBigPictureFullScreenToggle")
        showBigPictureFullScreenToggle = (storedBPToggle as? Bool) ?? true
        let storedLyricsLookup = UserDefaults.standard.object(forKey: "flactastic.lyricsLookupEnabled")
        lyricsLookupEnabled = (storedLyricsLookup as? Bool) ?? true
        let storedSaveLyrics = UserDefaults.standard.object(forKey: "flactastic.saveLyricsToFiles")
        saveLyricsToFiles = (storedSaveLyrics as? Bool) ?? true
        let storedVpn = UserDefaults.standard.object(forKey: "flactastic.showVpnNotice")
        showVpnNotice = (storedVpn as? Bool) ?? true
        spotifyClientID = UserDefaults.standard.string(forKey: "flactastic.spotifyClientID") ?? ""
        spotifyClientSecret = UserDefaults.standard.string(forKey: "flactastic.spotifyClientSecret") ?? ""
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
