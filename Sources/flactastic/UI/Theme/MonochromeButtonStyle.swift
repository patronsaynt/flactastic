import SwiftUI

/// Pill-shaped button for labels with text (e.g. "Play All", "Shuffle").
struct PillButtonStyle: ButtonStyle {
    var isPrimary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .fixedSize()
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
