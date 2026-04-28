import Foundation

/// Builds the "View artist" / "View artists…" context-menu entry for an album
/// or track credit string. Returns an empty array if the credit is missing —
/// callers can append the result unconditionally.
@MainActor
func artistContextMenuItems(
    credit: String?,
    library: LibraryStore,
    router: NavigationRouter
) -> [FLContextMenuItem] {
    let resolver = library.makeArtistResolver()
    let pieces = resolver.split(credit)
    guard !pieces.isEmpty else { return [] }

    if pieces.count == 1 {
        let piece = pieces[0]
        return [
            .button("View artist", systemImage: "person.crop.circle") {
                router.navigateToArtist(key: ArtistResolver.key(for: piece))
            }
        ]
    }

    let children: [FLContextMenuItem] = pieces.map { piece in
        .button(piece) {
            router.navigateToArtist(key: ArtistResolver.key(for: piece))
        }
    }
    return [.submenu("View artists…", systemImage: "person.2.crop.square.stack", items: children)]
}
