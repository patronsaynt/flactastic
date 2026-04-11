import SwiftUI

struct TopNavigationBar: View {
    @Binding var selectedTab: AppTab
    @Binding var searchText: String
    var onSettingsPressed: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            // App logo + name
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "record.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Text("FLACtastic")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.textPrimary)
            }

            Spacer()

            // Tab selector
            TabBarView(selectedTab: $selectedTab)

            Spacer()

            // Search + settings
            HStack(spacing: Theme.Spacing.md) {
                searchField
                settingsButton
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.background)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)

            TextField("Search...", text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.surface)
        )
    }

    private var settingsButton: some View {
        Button(action: onSettingsPressed) {
            Image(systemName: "gearshape")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }
}
