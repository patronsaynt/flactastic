import SwiftUI

/// Centered card container for the onboarding sequence — a 560pt-wide sheet
/// using the app's standard surface/divider/shadow treatment, matching the
/// design handoff's floating card.
struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 44)
            .padding(.top, 40)
            .padding(.bottom, 32)
            .frame(width: 560)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 40, y: 12)
    }
}

/// Shared "STEP N OF TOTAL" + title + subtitle header used by every
/// numbered onboarding step.
struct OnboardingStepHeader: View {
    let step: Int
    let total: Int
    var badge: String? = nil
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(Theme.Font.title)
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var eyebrow: String {
        let base = "STEP \(step) OF \(total)"
        guard let badge else { return base }
        return "\(base) · \(badge.uppercased())"
    }
}

/// Primary pill CTA used across onboarding steps. Thin wrapper around the
/// app's existing `PillButtonStyle` so onboarding buttons stay visually
/// identical to Settings' pill buttons.
extension View {
    func onboardingPrimaryButton() -> some View {
        buttonStyle(PillButtonStyle(isPrimary: true))
    }
}
