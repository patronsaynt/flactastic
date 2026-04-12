import SwiftUI

struct VolumeSliderView: View {
    @Environment(PlayerState.self) private var player
    @Environment(Settings.self) private var settings

    var body: some View {
        @Bindable var player = player
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)

            Slider(value: $player.volume, in: 0...1) { _ in
                settings.volume = player.volume
            }
            .tint(Theme.accent)
            .frame(width: 70)
            .onChange(of: player.volume) { _, newValue in
                player.engine.setVolume(newValue)
            }

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
