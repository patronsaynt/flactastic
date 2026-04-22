import SwiftUI

/// Full-bleed cover shown over the main UI while the initial library scan
/// and metadata load are in flight. Keeps album/track grids from visibly
/// reshuffling as tags stream in.
struct LoadingCoverView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "music.note")
                    .font(.system(size: 42, weight: .ultraLight))
                    .foregroundStyle(Theme.textSecondary)
                    .opacity(pulse ? 0.5 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                        value: pulse
                    )

                Text("Loading collection…")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.5)
            }
        }
        .onAppear { pulse = true }
    }
}
