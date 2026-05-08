import SwiftUI

/// Lyrics visualizer mode. Mirrors the Spectrum Horizontal layout: a
/// 720pt-max centered column with the lyrics scroller on top and an
/// album-art + title/artist details row below.
struct LyricsVisualizerView: View {
    @Environment(PlayerState.self)        private var player
    @Environment(Settings.self)           private var settings
    @Environment(LyricsRemoteCache.self)  private var cache
    @Environment(LyricsFetcher.self)      private var fetcher

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            topSection
                .frame(height: 280)

            detailsRow
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
    }

    // MARK: - Prefetch window

    /// Tracks adjacent to the current one whose lyrics should be warmed up
    /// in the background, so skipping forward / back feels instant.
    /// Window: previous track + next 2 — small enough to stay polite to
    /// lrclib, large enough to cover typical skip patterns.
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

    // MARK: - Top section

    @ViewBuilder
    private var topSection: some View {
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
                    // TimelineView keeps the active line index responsive at
                    // 10Hz without depending on PlayerState's tick cadence.
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        LyricsScrollerView(lyrics: lyrics,
                                           currentTime: player.currentTime)
                    }
                } else {
                    unavailable("Unable to find lyrics for this song")
                }
            } else if fetcher.hasRecentError(forKey: key) {
                // Transient network failure / timeout — surface a useful
                // message instead of spinning forever. Auto-clears on retry.
                unavailable("Unable to find lyrics for this song")
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // No track playing — empty state.
            Color.clear
        }
    }

    private func unavailable(_ message: String) -> some View {
        Text(message)
            .font(Theme.Font.title)
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Details row (mirror of SpectrumVisualizerView.horizontalDetails)

    private var detailsRow: some View {
        let track = player.currentTrack
        let artist = ArtistResolver.displayString(track?.artist) ?? "Unknown Artist"
        let album = track?.album?.trimmingCharacters(in: .whitespaces)
        return HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            ArtworkView(data: track?.artwork, size: 96)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: track?.title ?? "—",
                    font: .system(size: 22),
                    weight: .semibold,
                    foregroundStyle: AnyShapeStyle(Theme.textPrimary)
                )
                MarqueeText(
                    text: artist,
                    font: Theme.Font.bodyMedium,
                    foregroundStyle: AnyShapeStyle(Theme.textSecondary)
                )
                if let album, !album.isEmpty {
                    MarqueeText(
                        text: album,
                        font: Theme.Font.caption,
                        foregroundStyle: AnyShapeStyle(Theme.textTertiary)
                    )
                }
            }

            Spacer(minLength: 0)
        }
    }
}
