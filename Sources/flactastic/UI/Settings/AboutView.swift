import SwiftUI

/// "About FLACtastic" window contents — shown from the application menu.
struct AboutView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short ?? "beta"
    }

    var body: some View {
        VStack(spacing: 0) {
            Wordmark(height: 52)
                .padding(.bottom, Theme.Spacing.lg)

            Text("Version \(version)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Text("Lossless music, beautifully organized.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, Theme.Spacing.sm)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 44)
        .frame(width: 420)
        .background(Theme.background)
    }
}
