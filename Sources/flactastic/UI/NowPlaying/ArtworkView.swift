import SwiftUI

struct ArtworkView: View {
    @Environment(Settings.self) private var settings

    let data: Data?
    var size: CGFloat = 280

    private var cornerRadius: CGFloat {
        settings.roundedArtwork ? Theme.Radius.lg : 0
    }

    var body: some View {
        if let data, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.surfaceElevated)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.3, weight: .ultraLight))
                    .foregroundStyle(Theme.textTertiary.opacity(0.5))
            }
    }
}
