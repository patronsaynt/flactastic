import Foundation
import Testing
@testable import flactastic

@Test func audioFileFormatClassifyFlac() {
    let url = URL(fileURLWithPath: "/music/album/01 track.flac")
    #expect(AudioFileFormat.classify(url) == .flac)
}

@Test func audioFileFormatClassifyMp3() {
    let url = URL(fileURLWithPath: "/music/album/01 track.mp3")
    #expect(AudioFileFormat.classify(url) == .mp3)
}

@Test func audioFileFormatClassifyWav() {
    let url = URL(fileURLWithPath: "/music/album/01 track.wav")
    #expect(AudioFileFormat.classify(url) == .wav)
}

@Test func audioFileFormatClassifyAiff() {
    let url = URL(fileURLWithPath: "/music/album/01 track.aif")
    #expect(AudioFileFormat.classify(url) == .aiff)
    let url2 = URL(fileURLWithPath: "/music/album/01 track.aiff")
    #expect(AudioFileFormat.classify(url2) == .aiff)
}

@Test func audioFileFormatClassifyM4a() {
    let url = URL(fileURLWithPath: "/music/album/01 track.m4a")
    #expect(AudioFileFormat.classify(url) == .alac)
}

@Test func audioFileFormatClassifyCaseInsensitive() {
    #expect(AudioFileFormat.classify(pathExtension: "FLAC") == .flac)
    #expect(AudioFileFormat.classify(pathExtension: "Mp3") == .mp3)
    #expect(AudioFileFormat.classify(pathExtension: "WAV") == .wav)
}

@Test func audioFileFormatClassifyUnknown() {
    let url = URL(fileURLWithPath: "/music/readme.txt")
    #expect(AudioFileFormat.classify(url) == nil)
}

@Test func trackMakeFromURLValidFlac() {
    let url = URL(fileURLWithPath: "/Users/test/Music/MyAlbum/03 Song Title.flac")
    let track = Track.makeFromURL(url)
    #expect(track != nil)
    #expect(track?.title == "03 Song Title")
    #expect(track?.album == "MyAlbum")
    #expect(track?.fileFormat == .flac)
}

@Test func trackMakeFromURLInvalidExtension() {
    let url = URL(fileURLWithPath: "/Users/test/docs/notes.pdf")
    #expect(Track.makeFromURL(url) == nil)
}

@Test func trackSortedForLibrary() {
    let tracks = [
        Track(url: URL(fileURLWithPath: "/a"), title: "B Track", album: "B Album", trackNumber: 1, fileFormat: .flac),
        Track(url: URL(fileURLWithPath: "/b"), title: "A Track", album: "A Album", trackNumber: 2, fileFormat: .mp3),
        Track(url: URL(fileURLWithPath: "/c"), title: "C Track", album: "A Album", trackNumber: 1, fileFormat: .wav),
    ]
    let sorted = tracks.sortedForLibrary()
    #expect(sorted[0].title == "C Track")   // A Album, track 1
    #expect(sorted[1].title == "A Track")   // A Album, track 2
    #expect(sorted[2].title == "B Track")   // B Album, track 1
}

@Test func formatUtilsDuration() {
    #expect(FormatUtils.formatDuration(0) == "0:00")
    #expect(FormatUtils.formatDuration(65) == "1:05")
    #expect(FormatUtils.formatDuration(3661) == "1:01:01")
    #expect(FormatUtils.formatDuration(nil) == "--:--")
}

@Test func formatUtilsSampleRate() {
    #expect(FormatUtils.formatSampleRate(44100, bitDepth: 16) == "16/44")
    #expect(FormatUtils.formatSampleRate(96000, bitDepth: 24) == "24/96")
    #expect(FormatUtils.formatSampleRate(44100, bitDepth: nil) == "44.1 kHz")
    #expect(FormatUtils.formatSampleRate(nil, bitDepth: nil) == nil)
}

@Test func libraryScannerWithTempDirectory() async throws {
    let fm = FileManager.default
    let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tempDir) }

    // Create fake files (scanner only checks extensions, doesn't read content for the cheap pass).
    let subDir = tempDir.appendingPathComponent("TestAlbum")
    try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
    try Data().write(to: subDir.appendingPathComponent("01 Song.flac"))
    try Data().write(to: subDir.appendingPathComponent("02 Song.mp3"))
    try Data().write(to: subDir.appendingPathComponent("cover.jpg"))
    try Data().write(to: subDir.appendingPathComponent(".hidden.flac"))

    let scanner = LibraryScanner()
    let tracks = try await scanner.scan(root: tempDir)

    #expect(tracks.count == 2)
    #expect(tracks.allSatisfy { $0.album == "TestAlbum" })
    // Hidden files should be excluded
    #expect(tracks.allSatisfy { !$0.title.contains("hidden") })
    // Non-audio files excluded
    #expect(tracks.allSatisfy { $0.fileFormat == AudioFileFormat.flac || $0.fileFormat == AudioFileFormat.mp3 })
}
