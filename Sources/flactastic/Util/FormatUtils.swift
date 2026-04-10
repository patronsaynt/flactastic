import Foundation

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
