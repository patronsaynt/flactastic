import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)

            TextField("Search...", text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textPrimary)
                .focused($isFocused)
                .onExitCommand { isFocused = false }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.surface)
        )
        .onAppear { isFocused = false }
    }
}
