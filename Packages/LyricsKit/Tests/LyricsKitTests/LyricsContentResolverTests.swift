@testable import LyricsKit
import Testing

@Test func resolvesSynchronizedLyricsBeforePlainLyrics() {
    let result = LyricsResult(
        id: 1,
        trackName: "Song",
        artistName: "Artist",
        albumName: nil,
        duration: 60,
        instrumental: false,
        plainLyrics: "Plain line",
        syncedLyrics: "[00:01.00]Timed line"
    )

    let resolvedContent = LyricsContentResolver().resolve(result: result)

    if case let .synchronized(originalText, lines) = resolvedContent {
        #expect(originalText == "[00:01.00]Timed line")
        #expect(lines.map(\.text) == ["Timed line"])
    } else {
        Issue.record("Expected synchronized lyrics")
    }
}

@Test func fallsBackToNonemptyPlainLines() {
    let result = LyricsResult(
        id: 2,
        trackName: "Song",
        artistName: "Artist",
        albumName: nil,
        duration: 60,
        instrumental: false,
        plainLyrics: "First\n\n Second ",
        syncedLyrics: nil
    )

    let resolvedContent = LyricsContentResolver().resolve(result: result)

    if case let .plain(originalText, lines) = resolvedContent {
        #expect(originalText == "First\n\n Second")
        #expect(lines == ["First", "Second"])
    } else {
        Issue.record("Expected plain lyrics")
    }
}
