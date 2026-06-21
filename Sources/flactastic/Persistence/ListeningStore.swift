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

    private var currentRootURL: URL?

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

        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            events = try JSONDecoder().decode([PlayEvent].self, from: data)
        } catch {
            print("[ListeningStore] Failed to load listening history: \(error)")
        }
    }

    func save() {
        guard let url = fileURL else { return }
        do {
            let data = try JSONEncoder().encode(events)
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
            secondsListened: secondsListened,
            counted: counted
        )
        events.append(event)
        save()
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

    var totalSecondsListened: Double {
        events.reduce(0) { $0 + $1.secondsListened }
    }

    /// Distinct albums the listener has actually played (counted plays only).
    var albumsPlayedCount: Int {
        var albums = Set<String>()
        for event in events where event.counted {
            if let albumID = event.albumID { albums.insert(albumID) }
        }
        return albums.count
    }

    /// Total counted plays (each listen that cleared the ~90%-heard rule).
    var tracksPlayedCount: Int {
        events.filter(\.counted).count
    }

    /// Newest-first album summaries for the Recently Played rail, deduped so the
    /// same album doesn't appear twice in a row of recent listens.
    func recentlyPlayed(limit: Int) -> [RecentItem] {
        var seen = Set<String>()
        var result: [RecentItem] = []
        for event in events.sorted(by: { $0.date > $1.date }) {
            let key = event.albumID ?? event.trackID.uuidString
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(RecentItem(
                key: key,
                albumID: event.albumID,
                title: event.album ?? event.title,
                subtitle: event.artist ?? ""
            ))
            if result.count >= limit { break }
        }
        return result
    }

    /// Number of listening sessions — runs of events separated by gaps larger
    /// than `sessionGap`.
    var sessionCount: Int {
        let sorted = events.map(\.date).sorted()
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

    func topArtists(limit: Int) -> [RankedItem] {
        aggregate(key: { $0.artist }, since: nil)
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
            .filter { $0.plays > 0 }
            .sorted { $0.plays != $1.plays ? $0.plays > $1.plays : $0.minutes > $1.minutes }
            .prefix(limit)
            .map { $0 }
    }

    var topGenre: (name: String, share: Double)? {
        let counted = events.filter(\.counted)
        guard !counted.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for event in counted {
            guard let genre = event.genre, !genre.isEmpty else { continue }
            counts[genre, default: 0] += 1
        }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        return (top.key, Double(top.value) / Double(counted.count))
    }

    /// Generic count aggregation over a string key (e.g. artist), ranked by the
    /// number of counted plays.
    private func aggregate(key: (PlayEvent) -> String?, since: Date?) -> [RankedItem] {
        var counts: [String: Int] = [:]
        for event in events {
            if let since, event.date < since { continue }
            guard event.counted else { continue }
            guard let name = key(event), !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }
        return counts
            .map { RankedItem(name: $0.key, plays: $0.value) }
            .sorted { $0.plays > $1.plays }
    }
}

// MARK: - Metric value types

struct RecentItem: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let albumID: String?
    let title: String
    let subtitle: String
}

struct RankedItem: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let plays: Int
}

struct AlbumRank: Identifiable, Hashable {
    var id: String { albumID }
    let albumID: String
    let album: String
    let artist: String
    var plays: Int
    var minutes: Double
}
