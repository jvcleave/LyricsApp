import Foundation
@testable import LyricsKit
import Testing

struct FilenameMetadataParserTests {
    @Test(
        arguments: [
            ("Taylor Swift - Anti-Hero.mp3", "Taylor Swift", "Anti-Hero"),
            ("Taylor Swift - Anti-Hero.m4a", "Taylor Swift", "Anti-Hero"),
            ("Taylor Swift - Anti-Hero.caf", "Taylor Swift", "Anti-Hero"),
            ("01 - Taylor Swift - Anti-Hero.mp3", "Taylor Swift", "Anti-Hero"),
            ("Taylor_Swift_-_Anti-Hero.mp3", "Taylor Swift", "Anti-Hero"),
            ("Taylor Swift - Anti-Hero (Official Audio).mp3", "Taylor Swift", "Anti-Hero"),
            ("Taylor Swift - Anti-Hero (Official Video).mp4", "Taylor Swift", "Anti-Hero"),
            ("Taylor Swift - Anti-Hero [Official Music Video].mov", "Taylor Swift", "Anti-Hero"),
            (
                "The Strokes - Ode To The Mets (Official Video) [BjC0KUxiMhc].mp4",
                "The Strokes",
                "Ode To The Mets"
            ),
            (
                "BLACKPINK - 붐바야 (BOOMBAYAH) (Official 4K 60FPS Video) [GwxO7rc6OLw].quicktime.mp4",
                "BLACKPINK",
                "붐바야 (BOOMBAYAH) (Official 4K 60FPS Video)"
            ),
        ]
    )
    func parsesCommonFileNames(
        fileName: String,
        expectedArtist: String,
        expectedTitle: String
    ) {
        let result = FilenameMetadataParser().parse(
            fileURL: URL(fileURLWithPath: fileName)
        )

        #expect(result.artist == expectedArtist)
        #expect(result.title == expectedTitle)
    }
}
