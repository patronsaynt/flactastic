import SwiftUI

/// Standard chrome for modal sheets in FLACtastic.
///
/// Owns the title bar (title + close button), surface background, fixed frame,
/// top/bottom dividers, and the trailing `Spacer` that anchors the footer to
/// the bottom regardless of body height — preventing the "content centered in
/// a too-tall frame" layout bug that recurs when each sheet builds its own
/// `VStack` skeleton.
///
/// Use this for `.sheet`-presented modal editors. **Do not** use it for
/// popovers, menus, alerts, the queue panel, or `MenuBarExtra` content —
/// those have legitimately different layout needs.
///
/// For sheets with two body sections (e.g. a form above a track list),
/// include the intermediate divider yourself inside the `content` builder:
///
/// ```swift
/// FLSheet(title: "Edit Album", width: 540, height: 720) {
///     VStack(spacing: 0) {
///         formBody
///         Divider().foregroundStyle(Theme.divider)
///         trackListSection
///     }
/// } footer: {
///     HStack { Spacer(); Button("Cancel") { … }; Button("Save") { … } }
/// }
/// ```
struct FLSheet<Content: View, Footer: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var width: CGFloat = 520
    var height: CGFloat = 500
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().foregroundStyle(Theme.divider)
            // Greedy in height with top alignment: natural-height content sticks
            // to the top (header anchored, footer at bottom); greedy content
            // (e.g. a loading spinner using `maxHeight: .infinity`) fills the
            // whole region. Avoids fighting between content and a trailing
            // Spacer when both are vertically flexible.
            content()
                .frame(maxHeight: .infinity, alignment: .top)
            Divider().foregroundStyle(Theme.divider)
            footer()
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
        }
        .frame(width: width, height: height)
        .background(Theme.surface)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(Theme.Font.title)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xl)
    }
}
