import SwiftUI

enum Theme {
    static let background = Color.black
    static let surface = Color(white: 0.08)
    static let surfaceElevated = Color(white: 0.12)
    static let surfaceHover = Color(white: 0.16)

    static let textPrimary = Color(white: 0.95)
    static let textSecondary = Color(white: 0.65)
    static let textTertiary = Color(white: 0.45)

    static let divider = Color(white: 0.18)
    static let accent = Color.white

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }

    enum Font {
        static let body = SwiftUI.Font.system(.body)
        static let bodyMedium = SwiftUI.Font.system(.body, weight: .medium)
        static let caption = SwiftUI.Font.system(.caption)
        static let captionMono = SwiftUI.Font.system(.caption, design: .monospaced)
        static let title = SwiftUI.Font.system(.title2, weight: .semibold)
        static let headline = SwiftUI.Font.system(.headline)
    }
}
