import SwiftUI

/// Top-centered dropdown picker that fades in when the user hovers near
/// the top of the visualizer canvas. Lists every visualizer mode grouped
/// by category in a single neat menu.
struct VisualizerModePicker: View {
    @Binding var mode: VisualizerMode
    @State private var isHovering: Bool = false

    var body: some View {
        // Wrap the Menu in the capsule rather than putting the capsule on the
        // Menu's label — `.menuStyle(.borderlessButton)` strips backgrounds
        // applied inside the label, which left the picker as floating white
        // text against a light visualizer backdrop in light mode.
        HStack(spacing: Theme.Spacing.xs) {
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
                        .foregroundStyle(Color.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.55))
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
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
