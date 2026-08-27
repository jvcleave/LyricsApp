import Foundation
import Testing
@testable import LyricsApp

struct FilenameMetadataParserTests {
    @Test(
        arguments: [
            ("Taylor Swift - Anti-Hero.mp3", "Taylor Swift", "Anti-Hero"),
            ("01 - Taylor Swift - Anti-Hero.mp3", "Taylor Swift", "Anti-Hero"),
            ("Taylor_Swift_-_Anti-Hero.mp3", "Taylor Swift", "Anti-Hero"),
            ("Taylor Swift - Anti-Hero (Official Audio).mp3", "Taylor Swift", "Anti-Hero"),
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
