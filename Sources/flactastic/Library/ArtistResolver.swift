import Foundation

/// Identifies and parses artist credit strings against the set of canonical
/// artists known to the library. Splitting only happens when each fragment of
/// a separator-laden string matches a known canonical name, so legitimate
/// names like "Earth, Wind & Fire" stay intact.
struct ArtistResolver: Sendable {
    /// Maps normalised key → preferred display casing observed in tags.
    let canonicalByKey: [String: String]

    /// Build a resolver from a track collection. Canonical names are taken
    /// from any `albumArtist` or `artist` tag whose value contains no
    /// separator tokens — those are the strings we trust as full names.
    init(tracks: [Track]) {
        var byKey: [String: String] = [:]
        for track in tracks {
            for raw in [track.albumArtist, track.artist] {
                guard let raw, !raw.isEmpty else { continue }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !Self.containsSeparator(trimmed) else { continue }
                let key = Self.key(for: trimmed)
                if byKey[key] == nil { byKey[key] = trimmed }
            }
        }
        self.canonicalByKey = byKey
    }

    /// Stable lookup key: lowercased, diacritic-folded, whitespace-collapsed.
    static func key(for raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let collapsed = folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Display name for a key — uses the first observed casing from tags
    /// when available, otherwise echoes the key.
    func displayName(forKey key: String) -> String {
        canonicalByKey[key] ?? key
    }

    /// Parse a raw credit string into one or more artist names.
    /// - Strings containing the explicit delimiter (`;` or NUL) are always
    ///   split on those — that's how the track editor stores user-defined
    ///   artist lists, so they're authoritative.
    /// - Otherwise we attempt to split on common collaboration tokens
    ///   (feat./&/etc.) only when every fragment matches a known canonical
    ///   artist, so legitimate names like "Earth, Wind & Fire" stay intact.
    func split(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Explicit user-defined list.
        if let explicit = Self.explicitlySeparated(trimmed) { return explicit }

        // Fast path: the whole string is itself a known canonical name.
        if canonicalByKey[Self.key(for: trimmed)] != nil { return [trimmed] }
        if !Self.containsSeparator(trimmed) { return [trimmed] }

        let fragments = Self.splitOnSeparators(trimmed)
        let allKnown = fragments.allSatisfy { canonicalByKey[Self.key(for: $0)] != nil }
        return allKnown ? fragments : [trimmed]
    }

    /// If the string uses one of the explicit multi-artist delimiters, return
    /// the trimmed pieces. Otherwise nil.
    static func explicitlySeparated(_ raw: String) -> [String]? {
        // NUL and ";" are the app's own storage delimiters.
        // " / " (with spaces) is iTunes/Music.app's multi-artist delimiter —
        // spaces are required so names like "AC/DC" are left intact.
        for delimiter in ["\u{0000}", ";", " / "] {
            if raw.contains(delimiter) {
                return raw
                    .components(separatedBy: delimiter)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
        return nil
    }

    /// Canonical storage form for a list of explicitly-defined artists.
    /// Uses `" ; "` (space-semicolon-space) so the file tag remains readable
    /// in third-party editors while still being machine-parseable.
    static func joinExplicit(_ artists: [String]) -> String {
        artists
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ; ")
    }

    /// Display form for a credit string. Explicit lists render as
    /// `"A, B, C"`; everything else passes through unchanged.
    static func displayString(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if let pieces = explicitlySeparated(raw) {
            return pieces.joined(separator: ", ")
        }
        return raw
    }

    /// Returns the canonical keys this credit string resolves to, deduped
    /// while preserving order.
    func keys(forCredit raw: String?) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for piece in split(raw) {
            let k = Self.key(for: piece)
            if seen.insert(k).inserted { out.append(k) }
        }
        return out
    }

    // MARK: - Separator handling

    /// Tokens that count as artist-credit separators. Order matters: longer
    /// alternatives are tried first so "feat." doesn't get partially matched.
    private static let separatorPatterns: [String] = [
        " featuring ", " feat. ", " feat ", " ft. ", " ft ",
        " vs. ", " vs ",
        " with ",
        " & ", " x ", " X ",
        ", "
    ]

    static func containsSeparator(_ s: String) -> Bool {
        let padded = " \(s) "
        let lower = padded.lowercased()
        for token in separatorPatterns {
            if lower.contains(token.lowercased()) { return true }
        }
        return false
    }

    static func splitOnSeparators(_ s: String) -> [String] {
        var fragments: [String] = [s]
        for token in separatorPatterns {
            var next: [String] = []
            for piece in fragments {
                next.append(contentsOf: caseInsensitiveSplit(piece, separator: token))
            }
            fragments = next
        }
        return fragments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func caseInsensitiveSplit(_ s: String, separator: String) -> [String] {
        guard !separator.isEmpty else { return [s] }
        var pieces: [String] = []
        var remainder = s
        while let range = remainder.range(of: separator, options: .caseInsensitive) {
            pieces.append(String(remainder[..<range.lowerBound]))
            remainder = String(remainder[range.upperBound...])
        }
        pieces.append(remainder)
        return pieces
    }
}
