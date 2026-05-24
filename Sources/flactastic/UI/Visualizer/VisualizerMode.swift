import Foundation

enum VisualizerCategory: String, CaseIterable, Identifiable {
    case albumArt
    case lyrics
    case spectrum
    case bigPicture

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .albumArt:   return "Album Art"
        case .lyrics:     return "Lyrics"
        case .spectrum:   return "Spectrum"
        case .bigPicture: return "Big Picture"
        }
    }

    var modes: [VisualizerMode] {
        switch self {
        case .albumArt:
            return [.albumArtLarge, .albumArtLargeDetails,
                    .albumArtSmallDetails,
                    .albumArtWheel]
        case .lyrics:
            return [.lyrics]
        case .spectrum:
            return [.spectrumRadial, .spectrumHorizontal, .spectrogram]
        case .bigPicture:
            return [.bigPicture]
        }
    }
}

enum VisualizerMode: String, CaseIterable, Codable, Identifiable {
    case albumArtLarge
    case albumArtLargeDetails
    case albumArtSmallDetails
    case albumArtWheel
    case lyrics
    case spectrumRadial
    case spectrumHorizontal
    case spectrogram
    case bigPicture

    var id: String { rawValue }

    var category: VisualizerCategory {
        switch self {
        case .albumArtLarge, .albumArtLargeDetails,
             .albumArtSmallDetails,
             .albumArtWheel:
            return .albumArt
        case .lyrics:
            return .lyrics
        case .spectrumRadial, .spectrumHorizontal, .spectrogram:
            return .spectrum
        case .bigPicture:
            return .bigPicture
        }
    }

    /// Short label shown in the sub-option segmented row.
    var shortName: String {
        switch self {
        case .albumArtLarge:        return "Large"
        case .albumArtLargeDetails: return "Large + Details"
        case .albumArtSmallDetails: return "Small"
        case .albumArtWheel:        return "Wheel"
        case .lyrics:               return "Lyrics"
        case .spectrumRadial:       return "Radial"
        case .spectrumHorizontal:   return "Horizontal"
        case .spectrogram:          return "Spectrogram"
        case .bigPicture:           return "Big Picture"
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

    var showsDetails: Bool {
        switch self {
        case .albumArtLargeDetails, .albumArtSmallDetails,
             .spectrumRadial, .spectrumHorizontal:
            return true
        default:
            return false
        }
    }
}
