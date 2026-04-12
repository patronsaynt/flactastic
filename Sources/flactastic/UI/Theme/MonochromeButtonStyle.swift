import SwiftUI

struct MonochromeButtonStyle: ButtonStyle {
    var size: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(configuration.isPressed ? Theme.surfaceHover : Theme.surfaceElevated)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct PrimaryMonochromeButtonStyle: ButtonStyle {
    var size: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(Theme.background)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(configuration.isPressed ? Theme.textSecondary : Theme.textPrimary)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Pill-shaped button for labels with text (e.g. "Play All", "Shuffle").
struct PillButtonStyle: ButtonStyle {
    var isPrimary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isPrimary ? Theme.background : Theme.textPrimary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Capsule()
                    .fill(isPrimary
                          ? (configuration.isPressed ? Theme.textSecondary : Theme.textPrimary)
                          : (configuration.isPressed ? Theme.surfaceHover : Theme.surfaceElevated))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
