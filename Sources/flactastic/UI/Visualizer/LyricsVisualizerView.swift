import SwiftUI

/// Lyrics visualizer mode. Adopts the Big Picture layout — backdrop fills
/// the canvas, with the song details pinned to the bottom-left and the
/// karaoke-scrolling lyrics rendered large and left-justified above them.
/// The backdrop is a solid colour sampled from the album art (cross-fades
/// when the track changes), not the artist photo.
struct LyricsVisualizerView: View {
    @Environment(PlayerState.self)        private var player
    @Environment(Settings.self)           private var settings
    @Environment(LyricsRemoteCache.self)  private var cache
    @Environment(LyricsFetcher.self)      private var fetcher

    /// Cross-fade state for the backdrop colour. Mirrors the two-layer
    /// pattern used in `BigPictureVisualizerView`: previous colour stays
    /// underneath while the new colour fades in over it.
    @State private var currentColor: Color = Theme.background
    @State private var previousColor: Color = Theme.background
    @State private var currentOpacity: Double = 1
    @State private var displayedTrackID: UUID? = nil

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
        .background {
            backdrop
        }
        .task(id: player.currentTrack?.id) {
            let enabled = settings.lyricsLookupEnabled
            let save = settings.saveLyricsToFiles
            fetcher.ensureLyrics(
                for: player.currentTrack,
                enabled: enabled,
                saveToFile: save
            )
            fetcher.prefetch(
                tracks: adjacentTracks,
                enabled: enabled,
                saveToFile: save
            )
        }
        .onAppear { syncBackdrop(animated: false) }
        .onChange(of: player.currentTrack?.id) { _, _ in syncBackdrop(animated: true) }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            previousColor
            currentColor.opacity(currentOpacity)
            // Subtle vertical gradient keeps the bottom-left details legible
            // regardless of how light the dominant colour is.
            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
    }

    /// Recompute the backdrop colour when the track changes. With
    /// `animated: true` we run a 0.6s ease-in-out cross-fade; on first
    /// appearance we just set the colour directly.
    private func syncBackdrop(animated: Bool) {
        let trackID = player.currentTrack?.id
        let new = ArtistDetailView.dominantColor(from: player.currentTrack?.artwork)
            ?? Theme.background

        if !animated || displayedTrackID == nil {
            currentColor = new
            previousColor = new
            currentOpacity = 1
            displayedTrackID = trackID
            return
        }

        previousColor = currentColor
        currentColor = new
        currentOpacity = 0
        displayedTrackID = trackID
        withAnimation(.easeInOut(duration: 0.6)) {
            currentOpacity = 1
        }
    }

    // MARK: - Lyrics

    @ViewBuilder
    private var lyricsArea: some View {
        if !settings.lyricsLookupEnabled {
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
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        LyricsScrollerView(
                            lyrics: lyrics,
                            currentTime: player.currentTime,
                            alignment: .leading,
                            activeFont: .system(size: 34, weight: .bold),
                            inactiveFont: .system(size: 22, weight: .semibold),
                            activeStyle: AnyShapeStyle(Color.white),
                            inactiveStyle: AnyShapeStyle(Color.white.opacity(0.55))
                        )
                        .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                    }
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
            .font(Theme.Font.title)
            .foregroundStyle(Color.white.opacity(0.7))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Footer (matches Big Picture)

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
            }
            .frame(maxWidth: 720)
            .shadow(color: .black.opacity(0.55), radius: 5, y: 2)

            Spacer(minLength: 0)
        }
    }

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
                    Capsule().fill(.white.opacity(0.25)).frame(height: 3)
                    Capsule().fill(.white).frame(width: g.size.width * CGFloat(frac), height: 3)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 3)

            Text(FormatUtils.formatDuration(total > 0 ? total : nil))
                .monospacedDigit()
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))
        }
        .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
    }

    // MARK: - Prefetch window

    /// Tracks adjacent to the current one whose lyrics should be warmed up
    /// in the background, so skipping forward / back feels instant.
    private var adjacentTracks: [Track] {
        let q = player.queue
        guard !q.isEmpty else { return [] }
        let cur = player.currentIndex
        let offsets = [-1, 1, 2]
        return offsets.compactMap { delta in
            let idx = cur + delta
            return q.indices.contains(idx) ? q[idx] : nil
        }
    }
}
