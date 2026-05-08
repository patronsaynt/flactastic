import SwiftUI
import AppKit

/// Spotify-TV-style "Big Picture" mode. The artist's profile image fills the
/// canvas as a darkened backdrop; the track's album art and title/artist
/// sit in the bottom-left corner.
struct BigPictureVisualizerView: View {
    @Environment(PlayerState.self)        private var player
    @Environment(LibraryStore.self)       private var library
    @Environment(ArtistStore.self)        private var artistStore
    @Environment(ArtistRemoteCache.self)  private var artistRemoteCache
    @Environment(ArtistImageFetcher.self) private var artistImageFetcher
    @Environment(Settings.self)           private var settings

    /// Two-layer cross-fade state. `currentImage` shows on top of `previousImage`;
    /// when the backdrop key changes we move the now-current frame to `previousImage`,
    /// load the new one into `currentImage`, and animate `currentOpacity` from 0 → 1.
    @State private var currentImage: NSImage?
    @State private var previousImage: NSImage?
    @State private var currentOpacity: Double = 1
    @State private var displayedKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            footer
            progressBar
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background {
            backdrop
        }
        .task(id: player.currentTrack?.id) {
            ensureArtistImage()
        }
        .onAppear { syncBackdrop(animated: false) }
        .onChange(of: backdropIdentityKey) { _, _ in syncBackdrop(animated: true) }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            // Bottom layer: the previous image, fading out as the new one fades in.
            if let previousImage {
                Image(nsImage: previousImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Theme.background
            }

            // Top layer: the current image, opacity animated from 0 → 1.
            if let currentImage {
                Image(nsImage: currentImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(currentOpacity)
            }

            LinearGradient(
                colors: [.black.opacity(0.25), .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
    }

    /// Recompute the backdrop layers when the identity key changes. With
    /// `animated: true` we run a 0.6s ease-in-out cross-fade; with `false`
    /// (initial appearance) we just set the current image directly.
    private func syncBackdrop(animated: Bool) {
        let key = backdropIdentityKey
        guard key != displayedKey || currentImage == nil else { return }
        let newImage = backdropImageData.flatMap(NSImage.init(data:))

        if !animated || currentImage == nil {
            currentImage = newImage
            previousImage = nil
            currentOpacity = 1
            displayedKey = key
            return
        }

        // Move current → previous, prep new image off-screen, then fade in.
        previousImage = currentImage
        currentImage = newImage
        currentOpacity = 0
        displayedKey = key
        withAnimation(.easeInOut(duration: 0.6)) {
            currentOpacity = 1
        }
    }

    /// Stable identity for the current backdrop image. Prefers the artist
    /// key so consecutive tracks by the same artist don't re-fade.
    private var backdropIdentityKey: String {
        if let key = primaryArtistKey,
           artistStore.override(forKey: key)?.profileImage != nil
            || artistRemoteCache.entry(forKey: key)?.profileImage != nil {
            return "artist:\(key)"
        }
        if let id = player.currentTrack?.id {
            return "track:\(id.uuidString)"
        }
        return "empty"
    }

    // MARK: - Footer (art + text)

    private var footer: some View {
        let track = player.currentTrack
        let artist = ArtistResolver.displayString(track?.artist) ?? "Unknown Artist"
        return HStack(spacing: Theme.Spacing.lg) {
            ArtworkView(data: track?.artwork, size: 120)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                MarqueeText(
                    text: track?.title ?? "—",
                    font: .system(size: 36),
                    weight: .bold,
                    foregroundStyle: AnyShapeStyle(Color.white)
                )
                MarqueeText(
                    text: artist,
                    font: .system(size: 20),
                    weight: .regular,
                    foregroundStyle: AnyShapeStyle(Color.white.opacity(0.85))
                )
            }
            .frame(maxWidth: 760)
            .shadow(color: .black.opacity(0.6), radius: 6, y: 2)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Progress

    private var progressBar: some View {
        let total = player.duration ?? 0
        let current = player.currentTime
        let frac = total > 0 ? max(0, min(1, current / total)) : 0
        return HStack(spacing: Theme.Spacing.md) {
            Text(FormatUtils.formatDuration(current))
                .monospacedDigit()
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.25))
                        .frame(height: 3)
                    Capsule()
                        .fill(.white)
                        .frame(width: g.size.width * CGFloat(frac), height: 3)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 3)

            Text(FormatUtils.formatDuration(total > 0 ? total : nil))
                .monospacedDigit()
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))
        }
        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
    }

    // MARK: - Artist image lookup

    private var primaryArtistKey: String? {
        guard let credit = player.currentTrack?.artist ?? player.currentTrack?.albumArtist else {
            return nil
        }
        let resolver = library.makeArtistResolver()
        return resolver.keys(forCredit: credit).first
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
}
