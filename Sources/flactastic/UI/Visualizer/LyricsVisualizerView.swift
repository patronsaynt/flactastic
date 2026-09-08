import SwiftUI
import AppKit

/// Lyrics visualizer mode. The artist's profile image fills the canvas, blurred
/// and desaturated to a near-abstract ground, tinted toward the dominant colour
/// of the current album art and finished with film grain. Karaoke-scrolling
/// lyrics sit above the track details in the bottom-left.
struct LyricsVisualizerView: View {
    @Environment(PlayerState.self)        private var player
    @Environment(Settings.self)           private var settings
    @Environment(LibraryStore.self)       private var library
    @Environment(ArtistStore.self)        private var artistStore
    @Environment(ArtistRemoteCache.self)  private var artistRemoteCache
    @Environment(ArtistImageFetcher.self) private var artistImageFetcher
    @Environment(LyricsRemoteCache.self)  private var cache
    @Environment(LyricsFetcher.self)      private var fetcher

    /// Two-layer cross-fade state, mirroring the pattern the Big Picture mode
    /// used: the previous frame stays underneath while the new one fades in.
    /// Backdrop image and colour tint fade together on the same clock.
    @State private var currentImage: NSImage?
    @State private var previousImage: NSImage?
    @State private var currentOpacity: Double = 1
    @State private var displayedKey: String = ""
    /// First pass sets the backdrop outright; later ones cross-fade.
    @State private var hasDrawnBackdrop: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            lyricsArea
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                footer
                progressBar
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background { backdrop }
        .task(id: player.currentTrack?.id) {
            ensureArtistImage()
            guard player.currentTrack?.isMixCompilation != true else { return }
            let enabled = settings.lyricsLookupEnabled
            let save = settings.saveLyricsToFiles
            fetcher.ensureLyrics(
                for: player.currentTrack,
                enabled: enabled,
                saveToFile: save
            )
            fetcher.prefetch(
                tracks: adjacentTracks.filter { $0.isMixCompilation != true },
                enabled: enabled,
                saveToFile: save
            )
        }
        .task(id: backdropIdentityKey) {
            await syncBackdrop(animated: hasDrawnBackdrop)
            hasDrawnBackdrop = true
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            Theme.background

            // Both layers are already blurred, desaturated and darkened by
            // `VisualizerBackdropCache` — nothing here filters per frame.
            ZStack {
                if let previousImage {
                    Image(nsImage: previousImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                if let currentImage {
                    Image(nsImage: currentImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(currentOpacity)
                }
            }

            LinearGradient(
                colors: [.black.opacity(0.30), .black.opacity(0.80)],
                startPoint: .top, endPoint: .bottom
            )

            VisualizerFilmGrain()
        }
        .clipped()
    }

    /// Recompute the backdrop when the identity key changes. The expensive
    /// blur/desaturate pass runs off the main thread; with `animated: true` we
    /// then run a 0.6s ease-in-out cross-fade, and on first appearance we set
    /// the layers directly.
    private func syncBackdrop(animated: Bool) async {
        let key = backdropIdentityKey
        guard key != displayedKey || currentImage == nil else { return }
        // The dominant colour is part of what gets baked, so it belongs in the
        // cache key alongside the photo.
        let tint = VisualizerBackdropCache.Tint(
            ArtistDetailView.dominantColor(from: player.currentTrack?.artwork)
        )

        var newImage: NSImage?
        if let data = backdropImageData, !data.isEmpty {
            let imageKey = ArtworkImageCache.contentID(for: data) + "#" + (tint?.key ?? "none")
            // Fast path: a warm cache means no await, so returning to Lyrics
            // for a track we have already rendered costs nothing.
            if let hit = VisualizerBackdropCache.shared.cached(key: imageKey) {
                newImage = hit
            } else {
                newImage = await VisualizerBackdropCache.shared
                    .renderAsync(data: data, tint: tint, key: imageKey).image
                // The track may have moved on while we were rendering.
                guard key == backdropIdentityKey else { return }
            }
        }

        if !animated || currentImage == nil {
            currentImage = newImage
            previousImage = nil
            currentOpacity = 1
            displayedKey = key
            return
        }

        previousImage = currentImage
        currentImage = newImage
        currentOpacity = 0
        displayedKey = key
        withAnimation(.easeInOut(duration: 0.6)) {
            currentOpacity = 1
        }
    }

    /// Stable identity for the current backdrop. Prefers the artist key so
    /// consecutive tracks by the same artist don't re-fade the photo — but the
    /// colour tint is album-derived, so the track id still participates.
    private var backdropIdentityKey: String {
        let trackKey = player.currentTrack.map { "track:\($0.id.uuidString)" } ?? "empty"
        if let key = primaryArtistKey,
           artistStore.override(forKey: key)?.profileImage != nil
            || artistRemoteCache.entry(forKey: key)?.profileImage != nil {
            return "artist:\(key)|\(trackKey)"
        }
        return trackKey
    }

    // MARK: - Lyrics

    @ViewBuilder
    private var lyricsArea: some View {
        if player.currentTrack?.isMixCompilation == true {
            unavailable("Lyrics aren't available for mix compilations")
        } else if !settings.lyricsLookupEnabled {
            unavailable("Lyrics lookup disabled in Settings")
        } else if let track = player.currentTrack {
            let key = LyricsCacheKey.make(
                artist: track.artist ?? track.albumArtist,
                title: track.title,
                duration: track.duration
            )
            if let entry = cache.entry(forKey: key) {
                if entry.notFound {
                    unavailable("Unable to find lyrics for this song")
                } else if let lyrics = fetcher.parsedLyrics(from: entry, duration: track.duration ?? 0) {
                    TimedLyricsScroller(lyrics: lyrics)
                } else {
                    unavailable("Unable to find lyrics for this song")
                }
            } else if fetcher.hasRecentError(forKey: key) {
                unavailable("Unable to find lyrics for this song")
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            Color.clear
        }
    }

    private func unavailable(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.7))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        let track = player.currentTrack
        let artist = ArtistResolver.displayString(track?.artist) ?? "Unknown Artist"
        return HStack(spacing: Theme.Spacing.lg) {
            ArtworkView(data: track?.artwork, size: 96)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                MarqueeText(
                    text: track?.title ?? "—",
                    font: .system(size: 28),
                    weight: .bold,
                    foregroundStyle: AnyShapeStyle(Color.white)
                )
                MarqueeText(
                    text: artist,
                    font: .system(size: 16),
                    weight: .regular,
                    foregroundStyle: AnyShapeStyle(Color.white.opacity(0.85))
                )
                // Chrome here stays white regardless of app theme — it sits on
                // a darkened photo, not on the app's canvas.
                TechSpecLabel(track: track,
                              style: AnyShapeStyle(Color.white.opacity(0.5)))
            }
            .frame(maxWidth: 720)
            .shadow(color: .black.opacity(0.55), radius: 5, y: 2)

            Spacer(minLength: 0)
        }
    }

    private var progressBar: some View {
        PlaybackProgressBar(
            showsLabels: true,
            track: .white.opacity(0.25),
            fill: .white,
            glow: false,
            labelStyle: AnyShapeStyle(Color.white.opacity(0.85))
        )
        .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
    }

    // MARK: - Artist image lookup

    private var primaryArtistKey: String? {
        guard let credit = player.currentTrack?.artist ?? player.currentTrack?.albumArtist else {
            return nil
        }
        return library.makeArtistResolver().keys(forCredit: credit).first
    }

    private var backdropImageData: Data? {
        guard let key = primaryArtistKey else {
            return player.currentTrack?.artwork
        }
        if let override = artistStore.override(forKey: key)?.profileImage { return override }
        if let remote = artistRemoteCache.entry(forKey: key)?.profileImage { return remote }
        // Fall back to album art so the screen never looks empty while the
        // artist image is fetching.
        return player.currentTrack?.artwork
    }

    private func ensureArtistImage() {
        guard settings.autoFetchArtistImages,
              let key = primaryArtistKey,
              let credit = player.currentTrack?.artist ?? player.currentTrack?.albumArtist
        else { return }
        let resolver = library.makeArtistResolver()
        let display = resolver.displayName(forKey: key).isEmpty ? credit : resolver.displayName(forKey: key)
        artistImageFetcher.ensureImage(forKey: key, displayName: display)
    }

    // MARK: - Prefetch window

    /// Tracks adjacent to the current one whose lyrics should be warmed up
    /// in the background, so skipping forward / back feels instant.
    private var adjacentTracks: [Track] {
        let q = player.queue
        guard !q.isEmpty else { return [] }
        let cur = player.currentIndex
        return [-1, 1, 2].compactMap { delta in
            let idx = cur + delta
            return q.indices.contains(idx) ? q[idx] : nil
        }
    }
}

/// Drives `LyricsScrollerView` from the playback clock.
///
/// Split out so `LyricsVisualizerView` never reads `currentTime` in its own
/// body — otherwise the 20 Hz clock would re-evaluate the backdrop, artwork
/// and marquees along with the lyrics. See the note on `PlaybackProgressBar`.
private struct TimedLyricsScroller: View {
    @Environment(PlayerState.self) private var player
    let lyrics: Lyrics

    var body: some View {
        // Paused schedule: lyrics only advance with playback time, so ticking
        // at 10 Hz while paused is pure redraw waste.
        TimelineView(.animation(minimumInterval: 0.1, paused: !player.isPlaying)) { _ in
            LyricsScrollerView(
                lyrics: lyrics,
                currentTime: player.currentTime,
                alignment: .leading,
                activeStyle: AnyShapeStyle(Color.white)
            )
        }
    }
}
