import SwiftUI

struct TabBarView: View {
    @Binding var selectedTab: AppTab
    @Namespace private var tabAnimation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Theme.surface)
        )
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            Text(tab.rawValue)
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textTertiary)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Theme.surfaceElevated)
                            .matchedGeometryEffect(id: "activeTab", in: tabAnimation)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
