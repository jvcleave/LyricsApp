import Foundation
@testable import LyricsKit
import Testing

struct LyricsMatchInputTests {
    @Test func normalizesLookupTextForRemoteSearch() {
        let title = "마지막처럼 (AS IF IT'S YOUR LAST)"
            .decomposedStringWithCanonicalMapping
        let artist = "BLACKPINK".decomposedStringWithCanonicalMapping
        let album = "마지막처럼".decomposedStringWithCanonicalMapping

        let input = LyricsMatchInput(
            title: title,
            artist: artist,
            album: album,
            duration: 216.767
        )

        #expect(
            Array(input.title.unicodeScalars)
                == Array(title.precomposedStringWithCanonicalMapping.unicodeScalars)
        )
        #expect(
            Array(input.artist.unicodeScalars)
                == Array(artist.precomposedStringWithCanonicalMapping.unicodeScalars)
        )
        #expect(
            Array(input.album.unicodeScalars)
                == Array(album.precomposedStringWithCanonicalMapping.unicodeScalars)
        )
    }
}
