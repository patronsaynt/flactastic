import SwiftUI

struct OnboardingView: View {
    enum Step { case folder, theme }

    @Environment(Settings.self) private var settings
    @State private var step: Step = .folder

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            Group {
                switch step {
                case .folder:
                    OnboardingFolderPage(onAdvance: advanceToTheme)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                case .theme:
                    OnboardingThemePage(onContinue: completeOnboarding)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .id(step)
        }
    }

    private func advanceToTheme() {
        withAnimation(.easeInOut(duration: 0.28)) {
            step = .theme
        }
    }

    private func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.35)) {
            settings.hasCompletedOnboarding = true
        }
    }
}
