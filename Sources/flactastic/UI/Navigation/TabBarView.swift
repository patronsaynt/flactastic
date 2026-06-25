import SwiftUI

struct TabBarView: View {
    @Binding var selectedTab: AppTab
    @Namespace private var tabAnimation

    private let libraryTabs: [AppTab] = [.home, .collection, .playlists]
    private let toolTabs: [AppTab]    = [.download, .organizer, .visualizer]

    var body: some View {
        HStack(spacing: 2) {
            // Library group
            ForEach(libraryTabs) { tab in
                tabButton(tab)
            }

            // Visual divider between groups
            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1, height: 14)
                .padding(.horizontal, 3)

            // Tool group
            ForEach(toolTabs) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.surface)
        }
    }

    // MARK: - Tab button

    @ViewBuilder
    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(
                        size: 11,
                        weight: isSelected ? .semibold : .regular
                    ))
                    .symbolRenderingMode(.monochrome)
                    .scaleEffect(isSelected ? 1.05 : 1.0)

                Text(tab.rawValue)
                    .font(.system(
                        size: 12,
                        weight: isSelected ? .semibold : .medium
                    ))
            }
            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.surfaceElevated)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                        .matchedGeometryEffect(id: "activeTab", in: tabAnimation)
                }
            }
        }
        .buttonStyle(FluidTabButtonStyle())
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isSelected)
    }
}

// MARK: - Button style (press scale + colour fade)

private struct FluidTabButtonStyle: ButtonStyle {
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
