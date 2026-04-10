import SwiftUI

struct ArtworkView: View {
    let data: Data?
    var size: CGFloat = 280

    var body: some View {
        if let data, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.lg)
            .fill(Theme.surfaceElevated)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.3, weight: .ultraLight))
                    .foregroundStyle(Theme.textTertiary.opacity(0.5))
            }
    }
}
