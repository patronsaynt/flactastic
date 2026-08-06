import Foundation
import Testing
@testable import flactastic

// Tests for DownloadCoordinator.findExistingMatch — the "already in library"
// duplicate guard used by both the download pipeline and the playlist rebuild.

private func remoteTrack(
    title: String,
    artists: [String],
    album: String? = nil
) -> RemoteTrack {
    RemoteTrack(
        id: UUID().uuidString,
        title: title,
        artists: artists.map {
            RemoteArtist(id: UUID().uuidString, name: $0, url: nil, pictureURL: nil)
        },
        album: album.map {
            RemoteAlbumRef(id: UUID().uuidString, title: $0, url: nil,
                           coverArt: [], releaseYear: nil, trackCount: nil)
        },
        trackNumber: nil,
        discNumber: nil,
        durationSeconds: nil,
        coverArt: [],
        url: nil,
        serviceID: "test",
        isLossless: true
    )
}

private func libraryTrack(
    title: String,
    artist: String?,
    album: String? = nil,
    filename: String? = nil
) -> Track {
    Track(
        url: URL(fileURLWithPath: "/music/\(artist ?? "Unknown")/\(album ?? "Singles")/\(filename ?? title).flac"),
        title: title,
        artist: artist,
        album: album,
        fileFormat: .flac
    )
}

@Test @MainActor func sameTitleDifferentArtistIsNotADuplicate() {
    let library = [libraryTrack(title: "Song", artist: "Artist 2")]
    let remote = remoteTrack(title: "Song", artists: ["Artist 1"])
    #expect(DownloadCoordinator.findExistingMatch(for: remote, in: library) == nil)
}

@Test @MainActor func sameTitleSameArtistIsADuplicate() {
    let library = [libraryTrack(title: "Song", artist: "Artist 1")]
    let remote = remoteTrack(title: "Song", artists: ["Artist 1"])
    #expect(DownloadCoordinator.findExistingMatch(for: remote, in: library) != nil)
}

@Test @MainActor func artistMatchIsCaseInsensitive() {
    let library = [libraryTrack(title: "Song", artist: "ARTIST ONE")]
    let remote = remoteTrack(title: "Song", artists: ["artist one"])
    #expect(DownloadCoordinator.findExistingMatch(for: remote, in: library) != nil)
}

@Test @MainActor func multiArtistTagStillMatchesPrimaryArtist() {
    let library = [libraryTrack(title: "Song", artist: "Artist 1; Guest")]
    let remote = remoteTrack(title: "Song", artists: ["Artist 1"])
    #expect(DownloadCoordinator.findExistingMatch(for: remote, in: library) != nil)
}

@Test @MainActor func looseTitleMatchRequiresArtistOverlap() {
    // "Song (Radio Edit)" vs "Song - Radio Edit" flatten to the same loose key,
    // but a different artist must not be treated as a duplicate.
    let library = [libraryTrack(title: "Song - Radio Edit", artist: "Artist 2")]
    let remote = remoteTrack(title: "Song (Radio Edit)", artists: ["Artist 1"])
    #expect(DownloadCoordinator.findExistingMatch(for: remote, in: library) == nil)
}

@Test @MainActor func fileNameMatchWithDifferentArtistIsNotADuplicate() {
    // Same on-disk file name (e.g. "Song.flac") under another artist's folder
    // must not count as a duplicate when the remote track names its artist.
    let library = [libraryTrack(title: "Song", artist: "Artist 2", filename: "Song")]
    let remote = remoteTrack(title: "Song", artists: ["Artist 1"])
    #expect(DownloadCoordinator.findExistingMatch(for: remote, in: library) == nil)
}

@Test @MainActor func titleOnlyMatchAcceptedWhenRemoteHasNoArtistInfo() {
    // With nothing to disambiguate on, an exact title hit is the best we can do.
    let library = [libraryTrack(title: "Song", artist: "Artist 2")]
    let remote = remoteTrack(title: "Song", artists: [])
    #expect(DownloadCoordinator.findExistingMatch(for: remote, in: library) != nil)
}

@Test @MainActor func selfTitledSinglesByDifferentArtistsAreNotDuplicates() {
    // "Kiss" by Westwood vs "Kiss" by Lil Peep — both singles, so both album
    // names are "Kiss". The matching album must not override disjoint artists.
    let library = [libraryTrack(title: "Kiss", artist: "Lil Peep", album: "Kiss")]
    let remote = remoteTrack(title: "Kiss", artists: ["Westwood"], album: "Kiss")
    #expect(DownloadCoordinator.findExistingMatch(for: remote, in: library) == nil)
}

@Test @MainActor func albumOverlapDisambiguatesWhenArtistTagMissing() {
    // Library file has no artist tag, but the album matches — same recording.
    let library = [libraryTrack(title: "Song", artist: nil, album: "The Album")]
    let remote = remoteTrack(title: "Song", artists: ["Artist 1"], album: "The Album")
    #expect(DownloadCoordinator.findExistingMatch(for: remote, in: library) != nil)
}
