import SwiftUI

struct LyricsVisualizerView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Theme.textTertiary)
            Text("Lyrics")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.textSecondary)
            Text("Coming soon")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
