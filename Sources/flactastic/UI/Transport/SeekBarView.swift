import SwiftUI

struct SeekBarView: View {
    @Environment(PlayerState.self) private var player
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        @Bindable var player = player
        let duration = player.duration ?? 1
        let displayTime = isDragging ? dragValue : player.currentTime

        VStack(spacing: Theme.Spacing.xs) {
            Slider(
                value: isDragging ? $dragValue : $player.currentTime,
                in: 0...max(duration, 1)
            ) {
                Text("Seek")
            } onEditingChanged: { editing in
                if editing {
                    isDragging = true
                    dragValue = player.currentTime
                } else {
                    player.engine.seek(to: dragValue)
                    isDragging = false
                }
            }
            .tint(Theme.accent)

            HStack {
                Text(FormatUtils.formatDuration(displayTime))
                    .font(Theme.Font.captionMono)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                Spacer()
                Text("-\(FormatUtils.formatDuration(max(0, duration - displayTime)))")
                    .font(Theme.Font.captionMono)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
        }
    }
}
