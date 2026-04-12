import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            TextField("Search...", text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
                .focused($isFocused)
                .onExitCommand { isFocused = false }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.surfaceElevated)
        )
        .onAppear { isFocused = false }
    }
}
