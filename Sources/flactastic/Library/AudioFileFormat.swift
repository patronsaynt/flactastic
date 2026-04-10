import Foundation

enum AudioFileFormat: String, Sendable, CaseIterable, Hashable {
    case flac
    case mp3
    case wav
    case aiff
    case alac
    case aac

    var displayName: String {
        switch self {
        case .flac: return "FLAC"
        case .mp3: return "MP3"
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        case .alac: return "ALAC"
        case .aac: return "AAC"
        }
    }

    static func classify(_ url: URL) -> AudioFileFormat? {
        classify(pathExtension: url.pathExtension)
    }

    static func classify(pathExtension ext: String) -> AudioFileFormat? {
        switch ext.lowercased() {
        case "flac": return .flac
        case "mp3": return .mp3
        case "wav", "wave": return .wav
        case "aif", "aiff": return .aiff
        case "m4a": return .alac // ALAC or AAC, both decode fine; refined later via metadata
        case "aac": return .aac
        default: return nil
        }
    }
}
