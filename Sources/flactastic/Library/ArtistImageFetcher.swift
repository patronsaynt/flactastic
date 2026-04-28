import Foundation
import Observation

/// Coordinates lazy, deduplicated remote image fetches for artists.
/// User overrides always win — this only fills in artists with no override
/// and no fresh cache entry.
@Observable
@MainActor
final class ArtistImageFetcher {
    private let cache: ArtistRemoteCache
    private let store: ArtistStore
    private let client: DeezerClient
    private var inFlight: Set<String> = []

    init(
        cache: ArtistRemoteCache,
        store: ArtistStore,
        client: DeezerClient = .shared
    ) {
        self.cache = cache
        self.store = store
        self.client = client
    }

    /// Background prefetch every artist in the library that doesn't already
    /// have an image. Safe to call repeatedly — `ensureImage` no-ops on hits
    /// and on in-flight requests, and `DeezerClient` throttles concurrency.
    func prefetchAll(_ artists: [(key: String, displayName: String)]) {
        for artist in artists {
            ensureImage(forKey: artist.key, displayName: artist.displayName)
        }
    }

    /// Trigger a fetch if there's no override, no fresh cache entry, and no
    /// in-flight request for this key. Cheap to call from `.task { }` — no-ops
    /// when nothing needs to happen.
    func ensureImage(forKey key: String, displayName: String) {
        if let override = store.override(forKey: key), override.profileImage != nil {
            return
        }
        if cache.isFresh(forKey: key) { return }
        if inFlight.contains(key) { return }

        inFlight.insert(key)
        Task { [weak self] in
            await self?.fetch(key: key, displayName: displayName)
        }
    }

    private func fetch(key: String, displayName: String) async {
        defer { inFlight.remove(key) }
        do {
            guard let artist = try await client.searchArtist(name: displayName) else {
                cache.setEntry(ArtistRemoteEntry(canonicalKey: key, notFound: true))
                return
            }
            guard let url = artist.pictureURL else {
                cache.setEntry(ArtistRemoteEntry(canonicalKey: key, deezerId: artist.id, notFound: true))
                return
            }
            let data = try await client.downloadImage(url: url)
            cache.setEntry(ArtistRemoteEntry(
                canonicalKey: key,
                deezerId: artist.id,
                profileImage: data
            ))
        } catch {
            print("[ArtistImageFetcher] \(displayName): \(error)")
        }
    }
}

extension ArtistStore {
    /// Resolved profile image: user override wins, then remote cache.
    @MainActor
    func resolvedProfileImage(forKey key: String, remoteCache: ArtistRemoteCache) -> Data? {
        if let data = override(forKey: key)?.profileImage { return data }
        return remoteCache.entry(forKey: key)?.profileImage
    }
}
