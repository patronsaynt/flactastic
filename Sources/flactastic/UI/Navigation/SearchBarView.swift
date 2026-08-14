import SwiftUI

struct SearchBarView: View {
    /// `.rounded` is the original 8pt-radius field used by the top bar and the
    /// tool tabs. `.capsule` is the denser 34pt pill introduced with the
    /// Collection/Playlists redesign.
    enum Style {
        case rounded
        case capsule
    }

    @Binding var searchText: String
    var style: Style = .rounded

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            TextField(placeholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(style == .capsule ? .system(size: 12) : Theme.Font.bodyMedium)
                .foregroundStyle(Theme.textPrimary)
                .focused($isFocused)
                .onExitCommand { isFocused = false }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .modifier(SearchFieldChrome(style: style))
        .onAppear { isFocused = false }
    }

    private var placeholder: String {
        style == .capsule ? "Search…" : "Search..."
    }
}

private struct SearchFieldChrome: ViewModifier {
    let style: SearchBarView.Style

    func body(content: Content) -> some View {
        switch style {
        case .rounded:
            content
                .padding(.vertical, Theme.Spacing.sm)
                .frame(width: 200)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.surfaceElevated)
                )
        case .capsule:
            content
                .frame(width: 200, height: 34)
                .background(FLCapsuleBackground())
        }
    }
}
