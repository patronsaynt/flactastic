import SwiftUI

struct VisualizerView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Theme.textTertiary)

            Text("Visualizer")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.textSecondary)

            Text("Work in Progress")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
