import SwiftUI

/// First-run sequence: welcome, appearance, library folder, optional
/// Spotify connect, and a completion summary. Mirrors the Claude Design
/// handoff under `design_handoffs/onboarding-overhaul`.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, appearance, library, spotify, done
    }

    @Environment(Settings.self) private var settings
    @State private var step: Step = .welcome

    /// Called when the user finishes the sequence (taps "Enter FLACtastic").
    /// Defaults to marking onboarding complete in `Settings`. The debug
    /// preview window overrides this so testing the flow doesn't need to
    /// touch (already-true) persisted onboarding state — it just closes
    /// its own window instead.
    var onFinish: (() -> Void)?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            OnboardingCard {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Wordmark(height: 22)
                        Spacer()
                    }
                    .padding(.bottom, 26)

                    Group {
                        switch step {
                        case .welcome:
                            OnboardingWelcomePage(onNext: advance)
                        case .appearance:
                            OnboardingAppearancePage(onNext: advance)
                        case .library:
                            OnboardingLibraryPage(onNext: advance)
                        case .spotify:
                            OnboardingSpotifyPage(onNext: advance)
                        case .done:
                            OnboardingDonePage(onFinish: finish)
                        }
                    }
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            }
            .overlay(alignment: .topLeading) {
                if step != .welcome {
                    DetailBackButton(action: back)
                        .padding(.leading, 44)
                        .padding(.top, 40)
                }
            }
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.28)) { step = next }
    }

    private func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.28)) { step = previous }
    }

    private func finish() {
        if let onFinish {
            onFinish()
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                settings.hasCompletedOnboarding = true
            }
        }
    }
}
