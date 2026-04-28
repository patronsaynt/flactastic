import SwiftUI

/// Renders an artist credit string as one or more clickable chips that
/// navigate to the corresponding artist page. If the credit parses to a
/// single known artist the whole string is one button; otherwise each
/// known fragment becomes its own link with the original separators
/// rendered between them.
struct ArtistLink: View {
    let credit: String?
    var font: Font = Theme.Font.headline
    var color: Color = Theme.textSecondary

    @Environment(LibraryStore.self) private var library
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        let resolver = library.makeArtistResolver()
        let pieces = resolver.split(credit)

        if let credit, !credit.isEmpty {
            if pieces.count <= 1 {
                Button {
                    let key = ArtistResolver.key(for: pieces.first ?? credit)
                    router.navigateToArtist(key: key)
                } label: {
                    Text(pieces.first ?? credit)
                        .font(font)
                        .foregroundStyle(color)
                        .underline(false)
                }
                .buttonStyle(.plain)
                .help("View artist")
            } else {
                FlowText(pieces: pieces, font: font, color: color, router: router)
            }
        } else {
            Text("Unknown Artist")
                .font(font)
                .foregroundStyle(color)
        }
    }
}

private struct FlowText: View {
    let pieces: [String]
    let font: Font
    let color: Color
    let router: NavigationRouter

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { index, piece in
                if index > 0 {
                    Text(", ")
                        .font(font)
                        .foregroundStyle(color)
                }
                Button {
                    router.navigateToArtist(key: ArtistResolver.key(for: piece))
                } label: {
                    Text(piece)
                        .font(font)
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
                .help("View \(piece)")
            }
        }
    }
}
