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
    /// metadata" — ID3v2.3 + smaller cover art for old hardware. Off by
    /// default; modern players prefer the higher-quality default.
    var compatibility: Bool

    /// Output format. Mapped to the `downscale` field in the stream/v2
    /// request body. `.original` keeps the highest-quality source format
    /// the upstream service offers (FLAC for Qobuz/Tidal/Deezer hi-fi,
    /// MP3 for SoundCloud, AAC for Apple Music, etc.).
    var format: Format

    enum Format: String, CaseIterable, Sendable, Hashable, Identifiable {
        case original
        case flac
        case mp3
        case alac
        case aac
        case opus

        var id: String { rawValue }

        var label: String {
            switch self {
            case .original: return "Original (highest quality)"
            case .flac:     return "FLAC"
            case .mp3:      return "MP3"
            case .alac:     return "ALAC"
            case .aac:      return "AAC"
            case .opus:     return "Opus"
            }
        }
    }

    static let `default` = LucidaOptions(
        region: "auto",
        addMetadata: true,
        compatibility: false,
        format: .original
    )
}
