import SwiftUI

struct OnboardingSpotifyPage: View {
    @Environment(SpotifyAuthController.self) private var spotifyAuth
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            OnboardingStepHeader(
                step: 3, total: 3, badge: "Optional",
                title: "Bring in your playlists",
                subtitle: "Connect Spotify to match your playlists against your lossless library. You can skip this and add it anytime."
            )
            .riseFadeIn(delay: 0.0)

            spotifyRow
                .riseFadeIn(delay: 0.06)

            HStack(spacing: Theme.Spacing.lg) {
                Button("Skip for now", action: onNext)
                    .buttonStyle(.plain)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)

                connectButton
            }
            .riseFadeIn(delay: 0.1)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var spotifyRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.qualityCD.opacity(0.14))
                Image(systemName: "music.note.list")
                    .foregroundStyle(Theme.qualityCD)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Spotify")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.textPrimary)
                statusLabel
            }

            Spacer()

            if case .connecting = spotifyAuth.state {
                ProgressView().controlSize(.small)
            }
            if case .connected = spotifyAuth.state {
                ZStack {
                    Circle().fill(Theme.qualityCD.opacity(0.16))
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.qualityCD)
                }
                .frame(width: 22, height: 22)
            }
        }
        .padding(Theme.Spacing.md + 2)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(Theme.divider, lineWidth: 1)
        )
    }

    @ViewBuilder private var statusLabel: some View {
        switch spotifyAuth.state {
        case .disconnected:
            Text("Not connected")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
        case .connecting:
            Text("Connecting…")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textTertiary)
        case .connected(let name):
            Text("Connected as \(name)")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.qualityCD)
        }
    }

    @ViewBuilder private var connectButton: some View {
        switch spotifyAuth.state {
        case .disconnected:
            Button("Connect Spotify") {
                Task { await spotifyAuth.connect() }
            }
            .onboardingPrimaryButton()
        case .connecting:
            Button("Connecting…") {}
                .onboardingPrimaryButton()
                .disabled(true)
        case .connected:
            Button("Continue", action: onNext)
                .onboardingPrimaryButton()
        }
    }
}
