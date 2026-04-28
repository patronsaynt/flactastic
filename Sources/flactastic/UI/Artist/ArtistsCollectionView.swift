import SwiftUI

/// Top-level Artists grid for the Collection tab. Each cell links into
/// ArtistDetailView via the shared String-typed navigation stack.
struct ArtistsCollectionView: View {
    let searchText: String

    @Environment(LibraryStore.self) private var library
    @Environment(ArtistStore.self)  private var artistStore

    private var summaries: [ArtistSummary] {
        let resolver = library.makeArtistResolver()
        let all = library.allArtists(resolver: resolver, overrides: artistStore.overrides)
        guard !searchText.isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: Theme.Spacing.lg)],
                spacing: Theme.Spacing.xl
            ) {
                ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                    NavigationLink(value: NavigationRoute.artist(key: summary.id)) {
                        ArtistGridCell(
                            summary: summary,
                            preferredImage: artistStore.override(forKey: summary.id)
                                .flatMap { $0.profileImage ?? $0.bannerImage }
                        )
                    }
                    .buttonStyle(.plain)
                    .riseFadeIn(index: index)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, 100)
        }
    }
}
