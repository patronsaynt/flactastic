import SwiftUI
import AppKit

enum Theme {
    // MARK: - Adaptive Colors

    static let background = Color(nsColor: adaptive(
        dark: NSColor.black,
        light: NSColor(white: 0.96, alpha: 1)
    ))

    static let surface = Color(nsColor: adaptive(
        dark: NSColor(white: 0.08, alpha: 1),
        light: NSColor(white: 0.90, alpha: 1)
    ))

    static let surfaceElevated = Color(nsColor: adaptive(
        dark: NSColor(white: 0.12, alpha: 1),
        light: NSColor(white: 0.84, alpha: 1)
    ))

    static let surfaceHover = Color(nsColor: adaptive(
        dark: NSColor(white: 0.16, alpha: 1),
        light: NSColor(white: 0.78, alpha: 1)
    ))

    static let textPrimary = Color(nsColor: adaptive(
        dark: NSColor(white: 0.95, alpha: 1),
        light: NSColor(white: 0.08, alpha: 1)
    ))

    static let textSecondary = Color(nsColor: adaptive(
        dark: NSColor(white: 0.65, alpha: 1),
        light: NSColor(white: 0.35, alpha: 1)
    ))

    static let textTertiary = Color(nsColor: adaptive(
        dark: NSColor(white: 0.45, alpha: 1),
        light: NSColor(white: 0.55, alpha: 1)
    ))

    static let divider = Color(nsColor: adaptive(
        dark: NSColor(white: 0.18, alpha: 1),
        light: NSColor(white: 0.80, alpha: 1)
    ))

    static let accent = Color(nsColor: adaptive(
        dark: NSColor.white,
        light: NSColor.black
    ))

    // MARK: - Helpers

    private static func adaptive(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }

    // MARK: - Font

    enum Font {
        static let body = SwiftUI.Font.system(.body)
        static let bodyMedium = SwiftUI.Font.system(.body, weight: .medium)
        static let caption = SwiftUI.Font.system(.caption)
        static let captionMono = SwiftUI.Font.system(.caption)
        static let title = SwiftUI.Font.system(.title2, weight: .semibold)
        static let headline = SwiftUI.Font.system(.headline)
    }
}
