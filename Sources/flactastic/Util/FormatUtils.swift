import Foundation
import SwiftUI

/// Audio quality tiers based on sample rate and bit depth.
///
/// | Tier     | Criteria                          | Label          | Color      |
/// |----------|-----------------------------------|----------------|------------|
/// | Hi-Res   | >16-bit OR >44.1 kHz              | "Hi-Res"       | turquoise  |
/// | CD       | 16-bit / 44.1 kHz (Red Book)      | "CD"           | green      |
/// | Mid      | 256+ kbps lossy, or ≥16-bit <44.1 | "Mid"          | amber      |
/// | Low      | <256 kbps lossy / <16-bit         | "Low"          | red        |
enum AudioQuality: Sendable {
    case hiRes
    case cd
    case mid
    case low

    var label: String {
        switch self {
        case .hiRes: return "Hi-Res"
        case .cd:    return "CD"
        case .mid:   return "Mid"
        case .low:   return "Low"
        }
    }

    @MainActor
    var color: Color {
        switch self {
        case .hiRes: return Theme.qualityLossless
        case .cd:    return Theme.qualityCD
        case .mid:   return Theme.qualityMid
        case .low:   return Theme.qualityLow
        }
    }

    /// Determine quality tier from track metadata.
    static func classify(sampleRate: Double?, bitDepth: Int?, format: AudioFileFormat) -> AudioQuality {
        let rate = sampleRate ?? 0
        let bits = bitDepth ?? 0

        let isLossy = format == .mp3 || format == .aac

        if isLossy {
            // Lossy formats don't have meaningful bit depth / sample rate for quality.
            // MP3/AAC at standard rates are mid-tier at best.
            // Without bitrate info, classify by sample rate as proxy.
            if rate >= 44100 {
                return .mid
            } else {
                return .low
            }
        }

        // Lossless formats (FLAC, WAV, AIFF, ALAC)
        if bits > 16 || rate > 44100 {
            return .hiRes
        } else if bits == 16 && rate >= 44100 {
            return .cd
        } else if bits >= 16 || rate >= 44100 {
            return .cd
        } else if bits > 0 || rate > 0 {
            return .mid
        } else {
            // No metadata available — assume mid for lossless
            return .mid
        }
    }
}

enum FormatUtils {
    static func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    /// Coarser than `formatDuration` — "4h 12m" / "38m" — for aggregate
    /// lengths where seconds are noise.
    static func coarseDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0m" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : "\(m)m"
    }

    /// "64 tracks · 4h 12m" — the playlist card/row subtitle.
    static func playlistSummary(trackCount: Int, duration: TimeInterval) -> String {
        let tracks = "\(trackCount) track\(trackCount == 1 ? "" : "s")"
        guard duration > 0 else { return tracks }
        return "\(tracks) · \(coarseDuration(duration))"
    }

    static func formatSampleRate(_ rate: Double?, bitDepth: Int?) -> String? {
        guard let rate else { return nil }
        let khz = rate / 1000.0
        let rateStr: String
        if khz == khz.rounded() {
            rateStr = String(format: "%.0f kHz", khz)
        } else {
            rateStr = String(format: "%.1f kHz", khz)
        }
        if let bitDepth {
            return "\(bitDepth)/\(Int(khz))"
        }
        return rateStr
    }
}
