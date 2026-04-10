import SwiftUI

struct SeekBarView: View {
    @Environment(PlayerState.self) private var player
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        let duration = player.duration ?? 1
        let displayTime = isDragging ? dragValue : player.currentTime
        let progress = duration > 0 ? displayTime / duration : 0

        VStack(spacing: Theme.Spacing.xs) {
            GeometryReader { geo in
                let width = geo.size.width

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(Theme.surfaceElevated)
                        .frame(height: 4)

                    // Filled portion
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(0, min(CGFloat(progress) * width, width)), height: 4)

                    // Thumb
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 12, height: 12)
                        .offset(x: max(0, min(CGFloat(progress) * width - 6, width - 12)))
                }
                .frame(height: 12)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(value.location.x / width, 1))
                            let time = fraction * duration
                            if !isDragging {
                                isDragging = true
                            }
                            dragValue = time
                        }
                        .onEnded { value in
                            let fraction = max(0, min(value.location.x / width, 1))
                            let time = fraction * duration
                            player.engine.seek(to: time)
                            isDragging = false
                        }
                )
            }
            .frame(height: 16)

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
