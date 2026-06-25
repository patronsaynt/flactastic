import Foundation
import Observation

/// Session-scoped pick for the Home hero: a random lyric drawn from a song the
/// user already has in their library, plus the artist image used as a blurred
/// banner behind it. Created once at app launch and injected via `.environment`
/// so the same lyric persists across Home-tab revisits within a session and is
/// re-rolled on the next launch.
@Observable
@MainActor
final class HomeHighlight {
    struct Pick: Equatable {
        let lyric: String
        let songTitle: String
        let artistDisplay: String?
        /// Resolved artist image (or track artwork). `nil` → the hero shows a
        /// generic gray blob instead of a photo.
        let imageData: Data?
    }

    private(set) var pick: Pick?
    private var hasPicked = false

    /// How many tracks we're willing to read embedded lyrics from when the
    /// in-memory cache yields nothing. Bounds the worst-case tag I/O.
    private static let fileReadCap = 12

    /// Pick once per session. Runs off the main thread for the file-reading
    /// fallback so it never blocks launch. No-ops after the first attempt.
    func pickIfNeeded(
        library: LibraryStore,
        lyricsCache: LyricsRemoteCache,
        artistStore: ArtistStore,
        artistRemoteCache: ArtistRemoteCache,
        metadataWriter: MetadataWriter
    ) async {
        guard !hasPicked else { return }
        hasPicked = true

        let tracks = library.tracks
        guard !tracks.isEmpty else { return }

        let resolver = library.makeArtistResolver()

        // Map every library track to its lyrics-cache key (same formula the
        // fetcher uses) so cached entries resolve back to a real track.
        var trackByKey: [String: Track] = [:]
        for track in tracks {
            let key = LyricsCacheKey.make(
                artist: track.artist ?? track.albumArtist,
                title: track.title,
                duration: track.duration
            )
            if trackByKey[key] == nil { trackByKey[key] = track }
        }

        // ── Phase A: free, in-memory — already-cached lyrics ──
        let cachedEntries = lyricsCache.entries.values.filter { entry in
            !entry.notFound
                && (entry.plainLyrics?.isEmpty == false || entry.syncedLyrics?.isEmpty == false)
                && trackByKey[entry.key] != nil
        }
        for entry in cachedEntries.shuffled() {
            guard let track = trackByKey[entry.key] else { continue }
            let raw = (entry.syncedLyrics?.isEmpty == false ? entry.syncedLyrics : entry.plainLyrics) ?? ""
            if let line = Self.randomGoodLine(raw: raw, duration: track.duration) {
                finalize(track: track, line: line, resolver: resolver,
                         artistStore: artistStore, artistRemoteCache: artistRemoteCache)
                return
            }
        }

        // ── Phase B: bounded fallback — embedded file lyrics ──
        var reads = 0
        for track in tracks.shuffled() {
            guard reads < Self.fileReadCap else { break }
            reads += 1
            let raw = (try? await metadataWriter.readLyrics(from: track)) ?? nil
            guard let raw, !raw.isEmpty else { continue }
            if let line = Self.randomGoodLine(raw: raw, duration: track.duration) {
                finalize(track: track, line: line, resolver: resolver,
                         artistStore: artistStore, artistRemoteCache: artistRemoteCache)
                return
            }
        }
    }

    // MARK: - Helpers

    private func finalize(
        track: Track,
        line: String,
        resolver: ArtistResolver,
        artistStore: ArtistStore,
        artistRemoteCache: ArtistRemoteCache
    ) {
        let credit = track.artist ?? track.albumArtist
        let artistKey = resolver.keys(forCredit: credit).first
        let image = artistKey.flatMap {
            artistStore.resolvedProfileImage(forKey: $0, remoteCache: artistRemoteCache)
        } ?? track.artwork

        pick = Pick(
            lyric: line,
            songTitle: track.title,
            artistDisplay: ArtistResolver.displayString(credit),
            imageData: image
        )
    }

    /// Parse raw lyrics (synced or plain), keep only display-worthy lines, and
    /// return one at random. Returns nil when nothing usable is present.
    private static func randomGoodLine(raw: String, duration: TimeInterval?) -> String? {
        let parsed: Lyrics = raw.range(of: #"\[\d{1,2}:\d{2}"#, options: .regularExpression) != nil
            ? Lyrics.parseLRC(raw)
            : Lyrics.fromPlainText(raw, duration: duration ?? 0)

        let good = parsed.lines
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(isGoodLine)

        return good.randomElement().map(sanitizeQuotes)
    }

    /// The hero wraps the lyric in curly double quotes, so any double quotes
    /// *inside* the lyric (straight or typographic) are collapsed to single
    /// quotes to avoid nested-double-quote clutter.
    private static func sanitizeQuotes(_ text: String) -> String {
        var result = text
        for quote in ["\"", "\u{201C}", "\u{201D}"] {   // " “ ”
            result = result.replacingOccurrences(of: quote, with: "'")
        }
        return result
    }

    /// A line is display-worthy when it isn't empty, isn't a section/credit
    /// marker, and is short enough to stay within ~2 visual lines.
    private static func isGoodLine(_ text: String) -> Bool {
        // Upper bound keeps lyrics within ~2 lines once shrink-to-fit kicks in.
        guard text.count >= 6, text.count <= 130 else { return false }
        // Section markers like "[Chorus]" or "(Verse 2)" / "(x2)".
        if text.hasPrefix("[") { return false }
        if text.hasPrefix("(") && text.hasSuffix(")") { return false }
        return true
    }
}
