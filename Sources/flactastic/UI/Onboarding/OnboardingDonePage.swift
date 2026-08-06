import SwiftUI

struct OnboardingDonePage: View {
    @Environment(Settings.self) private var settings
    @Environment(SpotifyAuthController.self) private var spotifyAuth
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle().fill(Theme.qualityLossless.opacity(0.14))
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.qualityLossless)
            }
            .frame(width: 60, height: 60)
            .riseFadeIn(delay: 0.0)

            Text("You're all set")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.textPrimary)
                .riseFadeIn(delay: 0.04)

            Text("Your library is linked and ready. Time to hear it properly.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .riseFadeIn(delay: 0.08)

            VStack(spacing: Theme.Spacing.xs) {
                summaryRow("Appearance", settings.useLightMode ? "Light" : "Dark")
                summaryRow("Library", settings.lastRootPath.map(shortPath) ?? "—")
                summaryRow("Spotify", spotifySummary)
            }
            .frame(maxWidth: 320)
            .riseFadeIn(delay: 0.12)

            Button("Enter FLACtastic", action: onFinish)
                .onboardingPrimaryButton()
                .padding(.top, Theme.Spacing.xs)
                .riseFadeIn(delay: 0.16)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var spotifySummary: String {
        spotifyAuth.isConnected ? "Connected" : "Not connected"
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(value)
                .font(Theme.Font.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func shortPath(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
