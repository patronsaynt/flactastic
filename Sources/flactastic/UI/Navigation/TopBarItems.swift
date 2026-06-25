import SwiftUI

/// Settings entry point in the toolbar, styled to mirror a resting tab from
/// `TabBarView` — a surface-filled pill with an icon + label.
struct SettingsBarButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .regular))
                Text("Settings")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.surface)
            }
        }
        .buttonStyle(BarPressButtonStyle())
    }
}

/// Press feedback (scale + fade) matching the tab buttons in `TabBarView`.
struct BarPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.65),
                value: configuration.isPressed
            )
    }
}
