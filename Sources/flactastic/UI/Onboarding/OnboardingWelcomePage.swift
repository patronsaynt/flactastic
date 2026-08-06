import SwiftUI

struct OnboardingWelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("Welcome to FLACtastic")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .riseFadeIn(delay: 0.0)

            Text("Let's get your lossless library set up. It only takes a moment.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .riseFadeIn(delay: 0.06)

            Button("Get Started", action: onNext)
                .onboardingPrimaryButton()
                .padding(.top, Theme.Spacing.sm)
                .riseFadeIn(delay: 0.12)
        }
        .padding(.vertical, Theme.Spacing.xl)
    }
}
