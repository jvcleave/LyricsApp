import Foundation
@testable import LyricsKit
import Testing

struct LyricsLookupFallbackBuilderTests {
    @Test func removesOneTrailingWrappedGroupPerAttempt() {
        let input = LyricsMatchInput(
            title: "Song (Official Video) [Uploader] {Archive} (Remastered)",
            artist: "Artist",
            album: "Album",
            duration: 180
        )

        let inputs = LyricsLookupFallbackBuilder().inputs(startingWith: input)

        #expect(inputs.map(\.title) == [
            "Song (Official Video) [Uploader] {Archive} (Remastered)",
            "Song (Official Video) [Uploader] {Archive}",
            "Song (Official Video) [Uploader]",
            "Song (Official Video)",
            "Song",
        ])
        #expect(inputs.allSatisfy { $0.artist == "Artist" })
        #expect(inputs.allSatisfy { $0.album == "Album" })
        #expect(inputs.allSatisfy { $0.duration == 180 })
    }

    @Test func preservesWrappedTextThatIsNotATrailingAnnotation() {
        let input = LyricsMatchInput(
            title: "Song (Part 2) Finale",
            artist: "Artist",
            album: "",
            duration: nil
        )

        let inputs = LyricsLookupFallbackBuilder().inputs(startingWith: input)

        #expect(inputs.map(\.title) == ["Song (Part 2) Finale"])
    }

    @Test func removesATrailingGroupWithoutLeadingWhitespace() {
        let input = LyricsMatchInput(
            title: "Song(Live)",
            artist: "Artist",
            album: "",
            duration: nil
        )

        let inputs = LyricsLookupFallbackBuilder().inputs(startingWith: input)

        #expect(inputs.map(\.title) == ["Song(Live)", "Song"])
    }

    @Test func doesNotStripTheWholeTitle() {
        let input = LyricsMatchInput(
            title: "(Reprise)",
            artist: "Artist",
            album: "",
            duration: nil
        )

        let inputs = LyricsLookupFallbackBuilder().inputs(startingWith: input)

        #expect(inputs.map(\.title) == ["(Reprise)"])
    }

    @Test func handlesDownloadedVideoNameWithStackedExtensions() {
        let fileURL = URL(
            fileURLWithPath: "BLACKPINK - 붐바야 (BOOMBAYAH) (Official 4K 60FPS Video) [GwxO7rc6OLw].quicktime.mp4"
        )
        let metadata = FilenameMetadataParser().parse(fileURL: fileURL)
        let input = LyricsMatchInput(
            title: metadata.title,
            artist: metadata.artist,
            album: "",
            duration: nil
        )

        let inputs = LyricsLookupFallbackBuilder().inputs(startingWith: input)

        #expect(inputs.map(\.title) == [
            "붐바야 (BOOMBAYAH) (Official 4K 60FPS Video)",
            "붐바야 (BOOMBAYAH)",
            "붐바야",
        ])
        #expect(inputs.allSatisfy { $0.artist == "BLACKPINK" })
    }
}
