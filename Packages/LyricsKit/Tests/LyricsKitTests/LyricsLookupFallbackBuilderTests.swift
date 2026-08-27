import Foundation
@testable import LyricsKit
import Testing

struct LyricsLookupFallbackBuilderTests {
    @Test func removesOneTrailingWrappedGroupPerAttempt() {
        let input = LyricsMatchInput(
            title: "Song (Official Video) [Uploader] {Archive} (Remastered)",
            artist: "[4K] Artist",
            album: "Album (Deluxe)",
            duration: 180
        )

        let inputs = LyricsLookupFallbackBuilder().inputs(startingWith: input)

        #expect(inputs.map(\.title) == [
            "Song (Official Video) [Uploader] {Archive} (Remastered)",
            "Song",
            "Song (Official Video) [Uploader] {Archive}",
            "Song (Official Video) [Uploader]",
            "Song (Official Video)",
        ])
        #expect(inputs[0].artist == "[4K] Artist")
        #expect(inputs.dropFirst().allSatisfy { $0.artist == "Artist" })
        #expect(inputs[0].album == "Album (Deluxe)")
        #expect(inputs.dropFirst().allSatisfy { $0.album == "Album" })
        #expect(inputs.allSatisfy { $0.duration == 180 })
    }

    @Test func secondAttemptRemovesWrappedTextAnywhere() {
        let input = LyricsMatchInput(
            title: "Song (Part 2) Finale",
            artist: "[4K 60FPS] Artist",
            album: "",
            duration: nil
        )

        let inputs = LyricsLookupFallbackBuilder().inputs(startingWith: input)

        #expect(inputs.map(\.title) == ["Song (Part 2) Finale", "Song Finale"])
        #expect(inputs.map(\.artist) == ["[4K 60FPS] Artist", "Artist"])
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
            "붐바야",
            "붐바야 (BOOMBAYAH)",
        ])
        #expect(inputs.allSatisfy { $0.artist == "BLACKPINK" })
    }

    @Test func handlesKoreanDownloadedVideoName() {
        let fileURL = URL(
            fileURLWithPath: "BLACKPINK - 마지막처럼 (AS IF IT'S YOUR LAST) [Official 4K 60FPS Video] [hTkIPx1Lpuw].quicktime.mp4"
        )
        let metadata = FilenameMetadataParser().parse(fileURL: fileURL)
        let input = LyricsMatchInput(
            title: metadata.title,
            artist: metadata.artist,
            album: "",
            duration: 216.767
        )

        let inputs = LyricsLookupFallbackBuilder().inputs(startingWith: input)

        #expect(inputs.map(\.title) == [
            "마지막처럼 (AS IF IT'S YOUR LAST) [Official 4K 60FPS Video]",
            "마지막처럼",
            "마지막처럼 (AS IF IT'S YOUR LAST)",
        ])
        #expect(inputs.allSatisfy { $0.artist == "BLACKPINK" })
    }

    @Test func cleansLeadingVideoLabelFromArtistOnSecondAttempt() {
        let fileURL = URL(
            fileURLWithPath: "[4K 60FPS] BLACKPINK - GO [uTj-BeZuCMA].quicktime.mp4"
        )
        let metadata = FilenameMetadataParser().parse(fileURL: fileURL)
        let input = LyricsMatchInput(
            title: metadata.title,
            artist: metadata.artist,
            album: "",
            duration: 202.217
        )

        let inputs = LyricsLookupFallbackBuilder().inputs(startingWith: input)

        #expect(inputs.map(\.title) == ["GO", "GO"])
        #expect(inputs.map(\.artist) == ["[4K 60FPS] BLACKPINK", "BLACKPINK"])
    }
}
