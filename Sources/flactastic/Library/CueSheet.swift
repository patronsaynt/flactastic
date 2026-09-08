import Foundation

/// A single user-authored chapter/track marker within a Mix Compilation
/// track (a DJ mix, live set, radio show, or concert recording spanning
/// one audio file). Persisted by encoding a list of these into a CUESHEET
/// VorbisComment tag (see `CueSheet`) so markers travel with the file and
/// are visible to other cue-sheet-aware players/tools.
struct TrackMarker: Identifiable, Hashable, Sendable {
    let id: UUID
    var timestamp: TimeInterval
    var title: String

    init(id: UUID = UUID(), timestamp: TimeInterval, title: String) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
    }
}

extension Array where Element == TrackMarker {
    /// Markers ordered by timestamp — the canonical order for both display
    /// and the CUESHEET INDEX numbering.
    func sortedByTime() -> [TrackMarker] { sorted { $0.timestamp < $1.timestamp } }
}

extension TrackMarker {
    /// Parses "mm:ss", "m:ss", or "h:mm:ss" user input into seconds. Returns
    /// nil for anything unparsable (empty, non-numeric, too many/few parts).
    static func parseUserTimestamp(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        let numbers = parts.map { Double($0) }
        guard numbers.allSatisfy({ $0 != nil }) else { return nil }
        let values = numbers.compactMap { $0 }
        switch values.count {
        case 1:
            return values[0]
        case 2:
            return values[0] * 60 + values[1]
        case 3:
            return values[0] * 3600 + values[1] * 60 + values[2]
        default:
            return nil
        }
    }
}

/// Encodes/decodes a minimal, single-FILE embedded CUESHEET string
/// (the Xiph "CUESHEET" VorbisComment convention used by flac/metaflac,
/// foobar2000, etc. for one audio file with multiple indexed sections).
///
/// Format emitted (frame-based timestamps at the CD-standard 75 frames/sec):
/// ```
/// FILE "<basename>" WAVE
///   TRACK 01 AUDIO
///     TITLE "First section"
///     INDEX 01 00:00:00
///   TRACK 02 AUDIO
///     TITLE "Second section"
///     INDEX 01 03:15:37
/// ```
/// `mm:ss:ff` is minutes:seconds:frames (ff = 0-74, 75 frames/sec — the
/// standard cue-sheet unit, unrelated to the audio's own sample rate).
/// Track numbers are always two-digit, zero-padded, 1-based, contiguous
/// (01, 02, 03, …) regardless of any gaps in source data, since that's
/// what CUESHEET-consuming tools expect.
enum CueSheet {
    static func encode(markers: [TrackMarker], fileName: String) -> String {
        let ordered = markers.sortedByTime()
        var lines = ["FILE \"\(escapeQuotes(fileName))\" WAVE"]
        for (i, marker) in ordered.enumerated() {
            let n = String(format: "%02d", i + 1)
            lines.append("  TRACK \(n) AUDIO")
            let title = marker.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                lines.append("    TITLE \"\(escapeQuotes(title))\"")
            }
            lines.append("    INDEX 01 \(formatCueTimestamp(marker.timestamp))")
        }
        return lines.joined(separator: "\n")
    }

    static func decode(_ text: String) -> [TrackMarker] {
        var markers: [TrackMarker] = []
        var pendingTitle: String?
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("TRACK ") {
                pendingTitle = nil
            } else if line.hasPrefix("TITLE ") {
                pendingTitle = unquote(String(line.dropFirst("TITLE ".count)))
            } else if line.hasPrefix("INDEX 01 ") {
                let ts = String(line.dropFirst("INDEX 01 ".count)).trimmingCharacters(in: .whitespaces)
                if let seconds = parseCueTimestamp(ts) {
                    markers.append(TrackMarker(timestamp: seconds, title: pendingTitle ?? ""))
                }
            }
        }
        return markers.sortedByTime()
    }

    /// mm:ss:ff -> seconds (Double), ff/75.0 fractional part.
    static func parseCueTimestamp(_ s: String) -> TimeInterval? {
        let parts = s.split(separator: ":")
        guard parts.count == 3,
              let m = Int(parts[0]), let sec = Int(parts[1]), let f = Int(parts[2]) else { return nil }
        return Double(m * 60 + sec) + Double(f) / 75.0
    }

    static func formatCueTimestamp(_ seconds: TimeInterval) -> String {
        let totalFrames = Int((seconds * 75).rounded())
        let f = totalFrames % 75
        let totalSeconds = totalFrames / 75
        let s = totalSeconds % 60
        let m = totalSeconds / 60
        return String(format: "%02d:%02d:%02d", m, s, f)
    }

    private static func escapeQuotes(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "'") }

    private static func unquote(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 { t = String(t.dropFirst().dropLast()) }
        return t
    }
}
