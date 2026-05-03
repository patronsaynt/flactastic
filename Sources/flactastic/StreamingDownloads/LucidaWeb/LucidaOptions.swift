import Foundation

/// Per-track download knobs — mirrors the controls the lucida.to website
/// shows under a resolved track. Stored on `LucidaWebProvider` keyed by
/// `RemoteTrack.id`; the UI sets a track's options before calling
/// `DownloadCoordinator.enqueue(_:)`.
struct LucidaOptions: Sendable, Hashable {
    /// Region / "country" used to pick which licensed catalog to pull from.
    /// `auto` defers the choice to the lucida.to backend.
    var region: String

    /// When true, lucida.to embeds tags + cover art into the file before
    /// streaming it back. We still run our own `MetadataWriter` afterward,
    /// but starting from a tagged file is more robust for services that
    /// don't expose metadata via API.
    var addMetadata: Bool

    /// "Ensure compatibility with more players at the cost of quality of
    /// metadata" — ID3v2.3 + smaller cover art for old hardware.
    var compatibility: Bool

    /// Output format — passed as the *first* part of the `downscale` field.
    /// `original` returns the upstream service's native format unchanged
    /// (FLAC for Qobuz/Tidal hi-fi, MP3 for SoundCloud, AAC for Apple, …).
    var format: Format

    /// Quality preset value (e.g. `"320"`, `"16"`) — appended to `format`
    /// as `${format}-${quality}` when the format requires it. `nil` for
    /// formats that don't take a quality (original / wav / bitcrush).
    var quality: String?

    // MARK: - Format catalogue

    enum Format: String, Sendable, Hashable, Identifiable, CaseIterable {
        // Raw values are exactly what lucida.to puts before the `-quality`
        // suffix in the `downscale` field — keep them in sync with the
        // strings in the site's bundled JS.
        case original   = "original"
        case flac       = "flac"
        case mp3        = "mp3"
        case oggVorbis  = "ogg-vorbis"
        case opus       = "opus"
        case m4aAac     = "m4a-aac"
        case wav        = "wav"
        case bitcrush   = "bitcrush"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .original:  return "Original (highest quality)"
            case .flac:      return "FLAC"
            case .mp3:       return "MP3"
            case .oggVorbis: return "Ogg Vorbis"
            case .opus:      return "Opus"
            case .m4aAac:    return "M4A (AAC)"
            case .wav:       return "WAV"
            case .bitcrush:  return "Bitcrush"
            }
        }

        /// Formats that ffmpeg pipes raw — no quality suffix allowed.
        var requiresQuality: Bool {
            switch self {
            case .original, .wav, .bitcrush: return false
            default:                         return true
            }
        }

        /// Quality presets the lucida.to UI offers for this format.
        /// First entry is the highest-quality / default choice.
        var qualities: [Quality] {
            switch self {
            case .flac:
                return [Quality(value: "16", label: "16-bit 44.1 kHz")]
            case .mp3, .oggVorbis, .m4aAac:
                return [
                    Quality(value: "320", label: "320 kb/s"),
                    Quality(value: "256", label: "256 kb/s"),
                    Quality(value: "192", label: "192 kb/s"),
                    Quality(value: "128", label: "128 kb/s"),
                ]
            case .opus:
                return [
                    Quality(value: "320", label: "320 kb/s"),
                    Quality(value: "256", label: "256 kb/s"),
                    Quality(value: "192", label: "192 kb/s"),
                    Quality(value: "128", label: "128 kb/s"),
                    Quality(value: "96",  label: "96 kb/s"),
                    Quality(value: "64",  label: "64 kb/s"),
                ]
            case .original, .wav, .bitcrush:
                return []
            }
        }
    }

    struct Quality: Sendable, Hashable, Identifiable {
        let value: String
        let label: String
        var id: String { value }
    }

    // MARK: - Encoded value

    /// The full `downscale` string sent in the stream/v2 body.
    /// Always falls back to bare `format` when no quality is appropriate or
    /// set, so we never produce a malformed value like `"flac-"`.
    var downscale: String {
        guard format.requiresQuality, let q = quality, !q.isEmpty else {
            return format.rawValue
        }
        return "\(format.rawValue)-\(q)"
    }

    static let `default` = LucidaOptions(
        region: "auto",
        addMetadata: true,
        compatibility: false,
        format: .original,
        quality: nil
    )
}
