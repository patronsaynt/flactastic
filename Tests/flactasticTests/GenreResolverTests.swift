import Foundation
import Testing
@testable import flactastic

// MARK: - join

@Test func genreJoinPrimaryAndSecondaries() {
    #expect(GenreResolver.join(primary: "Rock", secondary: ["Pop", "Jazz"]) == "Rock ; Pop ; Jazz")
}

@Test func genreJoinPrimaryOnly() {
    #expect(GenreResolver.join(primary: "Rock", secondary: []) == "Rock")
}

@Test func genreJoinCapsAtThreeSecondaries() {
    let result = GenreResolver.join(primary: "Rock", secondary: ["Pop", "Jazz", "Soul", "Blues"])
    #expect(result == "Rock ; Pop ; Jazz ; Soul")
}

@Test func genreJoinDropsSecondaryEqualToPrimary() {
    #expect(GenreResolver.join(primary: "Rock", secondary: ["rock", "Pop"]) == "Rock ; Pop")
}

@Test func genreJoinDedupesSecondaries() {
    #expect(GenreResolver.join(primary: "Rock", secondary: ["Pop", "pop", "Jazz"]) == "Rock ; Pop ; Jazz")
}

@Test func genreJoinTrimsAndDropsEmpties() {
    #expect(GenreResolver.join(primary: "  Rock ", secondary: ["  ", "Pop  "]) == "Rock ; Pop")
}

@Test func genreJoinNilWhenEmpty() {
    #expect(GenreResolver.join(primary: nil, secondary: []) == nil)
    #expect(GenreResolver.join(primary: "  ", secondary: ["  "]) == nil)
}

@Test func genreJoinSecondaryOnlyHasNoPrimary() {
    // No primary but a secondary survives → it becomes the lone (first) value.
    #expect(GenreResolver.join(primary: nil, secondary: ["Pop"]) == "Pop")
}

// MARK: - split

@Test func genreSplitMultiValue() {
    let (primary, secondary) = GenreResolver.split("Rock ; Pop ; Jazz")
    #expect(primary == "Rock")
    #expect(secondary == ["Pop", "Jazz"])
}

@Test func genreSplitLegacySingleValueNoDelimiter() {
    let (primary, secondary) = GenreResolver.split("Rock")
    #expect(primary == "Rock")
    #expect(secondary.isEmpty)
}

@Test func genreSplitNilAndEmpty() {
    #expect(GenreResolver.split(nil).primary == nil)
    #expect(GenreResolver.split(nil).secondary.isEmpty)
    #expect(GenreResolver.split("").primary == nil)
    #expect(GenreResolver.split("   ").primary == nil)
}

@Test func genreSplitCapsAndDedupesSecondaries() {
    let (primary, secondary) = GenreResolver.split("Rock ; Pop ; Pop ; Jazz ; Soul ; Blues")
    #expect(primary == "Rock")
    #expect(secondary == ["Pop", "Jazz", "Soul"])
}

@Test func genreSplitHandlesITunesSlashDelimiter() {
    let (primary, secondary) = GenreResolver.split("Rock / Pop")
    #expect(primary == "Rock")
    #expect(secondary == ["Pop"])
}

// MARK: - round trip

@Test func genreRoundTrip() {
    let cases: [(String, [String])] = [
        ("Rock", ["Pop", "Jazz"]),
        ("Electronic", []),
        ("Hip-Hop", ["R&B", "Soul", "Funk"]),
    ]
    for (primary, secondary) in cases {
        let joined = GenreResolver.join(primary: primary, secondary: secondary)
        let (rp, rs) = GenreResolver.split(joined)
        #expect(rp == primary)
        #expect(rs == secondary)
    }
}
