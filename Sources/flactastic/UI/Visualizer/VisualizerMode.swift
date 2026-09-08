import Foundation

/// The visualizer's modes, in the order the left-edge mode wheel presents
/// them. `allCases` order is load-bearing — the wheel steps through it — so
/// keep it aligned with the design handoff's `MODES` array.
enum VisualizerMode: String, CaseIterable, Codable, Identifiable {
    case albumArtLarge
    case albumArtLargeDetails
    case albumArtSmallDetails
    case albumArtWheel
    case lyrics
    case spectrumRadial
    case spectrumHorizontal
    case spectrogram

    var id: String { rawValue }

    /// The full label shown on the mode wheel.
    var wheelLabel: String {
        switch self {
        case .albumArtLarge:        return "Large Art"
        case .albumArtLargeDetails: return "Large Art + Details"
        case .albumArtSmallDetails: return "Small Art + Details"
        case .albumArtWheel:        return "Cover Wheel"
        case .lyrics:               return "Lyrics"
        case .spectrumRadial:       return "Radial Spectrum"
        case .spectrumHorizontal:   return "Horizontal Spectrum"
        case .spectrogram:          return "Spectrogram"
        }
    }

    var requiresAudioTap: Bool {
        switch self {
        case .spectrumRadial, .spectrumHorizontal, .spectrogram:
            return true
        default:
            return false
        }
    }
}
