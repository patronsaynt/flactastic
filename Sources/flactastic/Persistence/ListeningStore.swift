import AppKit
import Foundation
import Observation

/// A single recorded listening event. One is appended each time a track stops
/// being the current track (skip, natural end, or library switch). Fields are
/// denormalized from `Track` so the home page can render history without a live
/// reference to the (possibly changed) library.
struct PlayEvent: Codable, Sendable, Identifiable {
    var id: UUID
    /// When the track *started* playing.
    var date: Date
    var trackID: UUID
    var title: String
    var artist: String?
    /// Album grouping key (`Album.id`), used to coalesce recently-played and
    /// rank top albums. Nil when the track had no album metadata.
    var albumID: String?
    var album: String?
    var genre: String?
    /// Secondary genres of the track at play time. Optional so existing
    /// `listening.json` files (which predate the field) still decode — the
    /// synthesized decoder would otherwise throw on the missing key.
    var secondaryGenres: [String]?
    var secondsListened: Double
    /// True when this listen qualified as a play under the streaming-style
    /// ~90%-heard rule (decided at record time, where the genuine listened
    /// time and track duration are both known). Sub-threshold listens are still
    /// logged so hours-listened stays accurate, but excluded from play counts.
    var counted: Bool

    init(
        id: UUID = UUID(),
        date: Date,
        trackID: UUID,
        title: String,
        artist: String? = nil,
        albumID: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        secondaryGenres: [String]? = nil,
        secondsListened: Double,
        counted: Bool
    ) {
        self.id = id
        self.date = date
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.albumID = albumID
        self.album = album
        self.genre = genre
        self.secondaryGenres = secondaryGenres
        self.secondsListened = secondsListened
        self.counted = counted
    }
}

/// Local-only, per-library listening history. Persists to
/// `<libraryRoot>/.flactastic/listening.json`, mirroring `PlaylistStore` so the
/// data travels with its library and switching libraries is a clean swap. Never
/// transmitted anywhere — the home page reads it in-process only.
@Observable
@MainActor
final class ListeningStore {
    private(set) var events: [PlayEvent] = []

    /// Intentionally-played albums/playlists, newest last. Distinct from
    /// `events` (which power stats): this only records when the user explicitly
    /// started a collection, so the Recently Played rail mirrors Spotify rather
    /// than surfacing an album for every single track that happened to play.
    private(set) var recentContexts: [RecentContext] = []

    private var currentRootURL: URL?

    /// On-disk container so events and recent contexts persist together while
    /// staying backward-compatible with files that held a bare `[PlayEvent]`.
    private struct PersistedData: Codable {
        var events: [PlayEvent]
        var contexts: [RecentContext]
    }

    /// Cap on stored recent contexts — far more than the rail shows.
    private static let maxRecentContexts = 50

    /// Gap (seconds) between consecutive events that starts a new session.
    private static let sessionGap: TimeInterval = 30 * 60

    private var fileURL: URL? {
        guard let rootURL = currentRootURL else { return nil }
        let dir = rootURL.appendingPathComponent(".flactastic", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("listening.json")
    }

    // MARK: - Persistence

    /// Point the store at `libraryRootURL` and replace in-memory events with
    /// that library's history (empty when the library has none). Switching back
    /// to a previous library restores its events intact.
    func load(from libraryRootURL: URL) {
        currentRootURL = libraryRootURL
        events = []
        recentContexts = []

        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            if let container = try? decoder.decode(PersistedData.self, from: data) {
                events = container.events
                recentContexts = container.contexts
            } else {
                // Legacy format: a bare array of events with no recent contexts.
                events = try decoder.decode([PlayEvent].self, from: data)
            }
        } catch {
            print("[ListeningStore] Failed to load listening history: \(error)")
        }
    }

    /// Async variant of `load(from:)` for app bootstrap: file read + JSON
    /// decode run off the main actor. The listening log grows with use, so
    /// the synchronous decode was a launch stall that scales with history.
    /// State is assigned only after the decode resolves, so nothing can
    /// observe (or save over) a half-switched store during the await.
    func loadAsync(from libraryRootURL: URL) async {
        let url = libraryRootURL
            .appendingPathComponent(".flactastic", isDirectory: true)
            .appendingPathComponent("listening.json")
        let loaded: PersistedData? = await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                if let container = try? decoder.decode(PersistedData.self, from: data) {
                    return container
                }
                // Legacy format: a bare array of events with no recent contexts.
                return PersistedData(events: try decoder.decode([PlayEvent].self, from: data), contexts: [])
            } catch {
                print("[ListeningStore] Failed to load listening history: \(error)")
                return nil
            }
        }.value
        currentRootURL = libraryRootURL
        events = loaded?.events ?? []
        recentContexts = loaded?.contexts ?? []
    }

    /// Serializes background writes: encode + atomic write happen off the
    /// main actor, in order, and a stale snapshot can never clobber a newer
    /// one (the generation guard drops out-of-order arrivals).
    private actor Persister {
        private var latestGeneration: UInt64 = 0

        func write(_ snapshot: PersistedData, generation: UInt64, to url: URL) {
            guard generation > latestGeneration else { return }
            latestGeneration = generation
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                print("[ListeningStore] Failed to save listening history: \(error)")
            }
        }
    }

    private let persister = Persister()
    @ObservationIgnored private var saveGeneration: UInt64 = 0

    init() {
        // Detached save tasks don't get a chance to run once the app begins
        // tearing down, so flush synchronously at quit — otherwise the last
        // track's play event could be lost.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    /// Snapshot current state and persist it off the main actor. The events
    /// array grows unboundedly with listening history, so encoding it
    /// synchronously here (once per track change) produced main-thread stalls
    /// that scale with how long the user has had the app.
    func save() {
        guard let url = fileURL else { return }
        saveGeneration &+= 1
        let generation = saveGeneration
        let snapshot = PersistedData(events: events, contexts: recentContexts)
        Task.detached(priority: .utility) { [persister] in
            await persister.write(snapshot, generation: generation, to: url)
        }
    }

    /// Synchronous write for app termination.
    private func saveNow() {
        guard let url = fileURL else { return }
        saveGeneration &+= 1
        do {
            let data = try JSONEncoder().encode(PersistedData(events: events, contexts: recentContexts))
            try data.write(to: url, options: .atomic)
        } catch {
            print("[ListeningStore] Failed to save listening history: \(error)")
        }
    }

    // MARK: - Recording

    /// Append a play event for `track`, having heard `secondsListened`. No-op
    /// for negligible listens (< 1 s) so momentary track flips don't pollute the
    /// log. Persists immediately — the volume of events is low (one per track
    /// played) so an atomic write per event is cheap.
    func record(track: Track, startedAt: Date, secondsListened: Double, counted: Bool) {
        // Drop negligible listens that also didn't count, so momentary track
        // flips don't pollute the log. A counted play is always recorded.
        guard counted || secondsListened >= 1 else { return }
        let event = PlayEvent(
            date: startedAt,
            trackID: track.id,
            title: track.title,
            artist: track.artist ?? track.albumArtist,
            albumID: Self.albumID(for: track),
            album: track.album,
            genre: track.genre,
            secondaryGenres: track.secondaryGenres,
            secondsListened: secondsListened,
            counted: counted
        )
        events.append(event)
        save()
    }

    /// Record that the user intentionally started playing a collection (an album
    /// or a playlist). Collapses any prior entry for the same item so it jumps to
    /// the front, and caps the stored history.
    func recordContextPlay(kind: RecentKind, targetID: String, title: String, subtitle: String) {
        recentContexts.removeAll { $0.kind == kind && $0.targetID == targetID }
        recentContexts.append(RecentContext(
            kind: kind, targetID: targetID, title: title, subtitle: subtitle, date: .now
        ))
        if recentContexts.count > Self.maxRecentContexts {
            recentContexts.removeFirst(recentContexts.count - Self.maxRecentContexts)
        }
        save()
    }

    /// Convenience: record an intentional album play for the Recently Played rail.
    func recordAlbumPlay(_ album: Album) {
        let subtitle = album.isCompilation
            ? "Compilation"
            : (ArtistResolver.displayString(album.artist) ?? "Unknown Artist")
        recordContextPlay(kind: .album, targetID: album.id, title: album.name, subtitle: subtitle)
    }

    /// Convenience: record an intentional playlist play for the Recently Played rail.
    func recordPlaylistPlay(_ playlist: Playlist) {
        recordContextPlay(
            kind: .playlist,
            targetID: playlist.id.uuidString,
            title: playlist.name,
            subtitle: "Playlist"
        )
    }

    /// Album grouping key matching `LibraryStore.albums` so recently-played and
    /// top-albums coalesce the same way the Collection does.
    private static func albumID(for track: Track) -> String? {
        guard let album = track.album else { return nil }
        let artist = track.albumArtist ?? track.artist ?? "Unknown Artist"
        return "\(artist)|\(album)"
    }

    // MARK: - Metrics

    var hasHistory: Bool { !events.isEmpty }

    /// Events on or after `since` (all events when `since` is nil). Backs the
    /// time-range filter on the home page.
    private func filtered(_ since: Date?) -> [PlayEvent] {
        guard let since else { return events }
        return events.filter { $0.date >= since }
    }

    func totalSecondsListened(since: Date? = nil) -> Double {
        filtered(since).reduce(0) { $0 + $1.secondsListened }
    }

    /// Distinct albums the listener has actually played (counted plays only).
    func albumsPlayedCount(since: Date? = nil) -> Int {
        var albums = Set<String>()
        for event in filtered(since) where event.counted {
            if let albumID = event.albumID { albums.insert(albumID) }
        }
        return albums.count
    }

    /// Total counted plays (each listen that cleared the ~90%-heard rule).
    func tracksPlayedCount(since: Date? = nil) -> Int {
        filtered(since).filter(\.counted).count
    }

    /// Newest-first collections (albums/playlists) the user intentionally
    /// played, for the Recently Played rail.
    func recentlyPlayed(limit: Int) -> [RecentItem] {
        recentContexts
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { RecentItem(kind: $0.kind, targetID: $0.targetID, title: $0.title, subtitle: $0.subtitle) }
    }

    /// Number of listening sessions — runs of events separated by gaps larger
    /// than `sessionGap`.
    func sessionCount(since: Date? = nil) -> Int {
        let sorted = filtered(since).map(\.date).sorted()
        guard !sorted.isEmpty else { return 0 }
        var count = 1
        for i in 1..<sorted.count where sorted[i].timeIntervalSince(sorted[i - 1]) > Self.sessionGap {
            count += 1
        }
        return count
    }

    /// Consecutive days (ending today or yesterday) with at least one play.
    var currentStreakDays: Int {
        let cal = Calendar.current
        let days = Set(events.map { cal.startOfDay(for: $0.date) })
        guard !days.isEmpty else { return 0 }

        let today = cal.startOfDay(for: Date())
        // Allow the streak to be "alive" if the user listened today OR yesterday.
        var cursor = today
        if !days.contains(today) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Minutes listened for each of the last 7 days, oldest → newest (Mon-style
    /// ordering is applied by the view). Index 6 is today.
    func weeklyMinutes() -> [Double] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var buckets = [Double](repeating: 0, count: 7)
        for event in events {
            let day = cal.startOfDay(for: event.date)
            guard let diff = cal.dateComponents([.day], from: day, to: today).day,
                  diff >= 0, diff < 7 else { continue }
            buckets[6 - diff] += event.secondsListened / 60.0
        }
        return buckets
    }

    /// Weekday short labels aligned to `weeklyMinutes()` (index 6 = today).
    func weeklyDayLabels() -> [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            return fmt.string(from: day)
        }
    }

    func topArtists(limit: Int, since: Date? = nil) -> [RankedItem] {
        aggregate(key: { $0.artist }, since: since)
            .prefix(limit)
            .map { $0 }
    }

    func topAlbumsThisWeek(limit: Int) -> [AlbumRank] {
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var byAlbum: [String: AlbumRank] = [:]
        for event in events where event.date >= weekAgo {
            guard let albumID = event.albumID else { continue }
            var rank = byAlbum[albumID] ?? AlbumRank(
                albumID: albumID,
                album: event.album ?? "Unknown Album",
                artist: event.artist ?? "",
                plays: 0,
                minutes: 0
            )
            if event.counted { rank.plays += 1 }
            rank.minutes += event.secondsListened / 60.0
            byAlbum[albumID] = rank
        }
        return byAlbum.values
            .filter { $0.minutes > 0 }
            .sorted {
                // Rank purely by minutes listened; plays then title break ties
                // so the order stays stable across recomputes.
                if $0.minutes != $1.minutes { return $0.minutes > $1.minutes }
                if $0.plays != $1.plays { return $0.plays > $1.plays }
                return $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    func topGenre(since: Date? = nil) -> (name: String, share: Double)? {
        let counted = filtered(since).filter(\.counted)
        guard !counted.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for event in counted {
            // Count the primary genre and every secondary genre at equal
            // weight, deduped within the event (case-insensitive) so one play
            // never double-counts a genre.
            var genresForEvent: [String] = []
            if let g = event.genre, !g.isEmpty { genresForEvent.append(g) }
            genresForEvent.append(contentsOf: (event.secondaryGenres ?? []).filter { !$0.isEmpty })

            var seen = Set<String>()
            for g in genresForEvent where seen.insert(g.lowercased()).inserted {
                counts[g, default: 0] += 1
            }
        }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        return (top.key, Double(top.value) / Double(counted.count))
    }

    /// Generic aggregation over a string key (e.g. artist), ranked purely by the
    /// genuine minutes spent listening. `plays` is carried alongside for display.
    private func aggregate(key: (PlayEvent) -> String?, since: Date?) -> [RankedItem] {
        var minutes: [String: Double] = [:]
        var plays: [String: Int] = [:]
        for event in events {
            if let since, event.date < since { continue }
            guard let name = key(event), !name.isEmpty else { continue }
            minutes[name, default: 0] += event.secondsListened / 60.0
            if event.counted { plays[name, default: 0] += 1 }
        }
        return minutes
            .map { RankedItem(name: $0.key, plays: plays[$0.key] ?? 0, minutes: $0.value) }
            // Rank by minutes; break ties alphabetically so equal entries keep a
            // stable order across recomputes rather than reshuffling.
            .sorted {
                $0.minutes != $1.minutes
                    ? $0.minutes > $1.minutes
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}

// MARK: - Metric value types

/// What kind of collection a Recently Played entry points at.
enum RecentKind: String, Codable, Sendable {
    case album
    case playlist
}

/// A persisted "you played this" entry for the Recently Played rail.
struct RecentContext: Codable, Sendable, Hashable {
    var kind: RecentKind
    /// `Album.id` for albums, or the playlist's UUID string for playlists.
    var targetID: String
    var title: String
    var subtitle: String
    var date: Date
}

struct RecentItem: Identifiable, Hashable {
    let kind: RecentKind
    let targetID: String
    let title: String
    let subtitle: String
    var id: String { "\(kind.rawValue):\(targetID)" }
}

struct RankedItem: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let plays: Int
    /// Total genuine minutes spent listening — the basis for ranking.
    let minutes: Double
}

struct AlbumRank: Identifiable, Hashable {
    var id: String { albumID }
    let albumID: String
    let album: String
    let artist: String
    var plays: Int
    var minutes: Double
}
