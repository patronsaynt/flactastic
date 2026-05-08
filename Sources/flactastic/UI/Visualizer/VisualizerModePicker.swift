import SwiftUI

/// Top-centered dropdown picker that fades in when the user hovers near
/// the top of the visualizer canvas. Lists every visualizer mode grouped
/// by category in a single neat menu.
struct VisualizerModePicker: View {
    @Binding var mode: VisualizerMode
    @State private var isHovering: Bool = false

    var body: some View {
        Menu {
            ForEach(VisualizerCategory.allCases) { category in
                Section(category.displayName) {
                    ForEach(category.modes) { subMode in
                        Button {
                            mode = subMode
                        } label: {
                            if subMode == mode {
                                Label(menuLabel(for: subMode), systemImage: "checkmark")
                            } else {
                                Text(menuLabel(for: subMode))
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(currentLabel)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Capsule()
                    .fill(Theme.surface.opacity(0.9))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(isHovering ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var currentLabel: String {
        if mode.category.modes.count > 1 {
            return "\(mode.category.displayName) — \(mode.shortName)"
        }
        return mode.category.displayName
    }

    private func menuLabel(for subMode: VisualizerMode) -> String {
        subMode.category.modes.count > 1 ? subMode.shortName : subMode.category.displayName
    }
}
