import Testing
@testable import LyricsApp

struct LRCParserTests {
    @Test
    func parsesHundredthsTimestampAndText() throws {
        let line = try #require(LRCParser().parse("[00:17.12]Hello world").first)

        #expect(abs(line.time - 17.12) < 0.0001)
        #expect(line.text == "Hello world")
    }

    @Test
    func parsesMillisecondsAndSortsLines() {
        let lines = LRCParser().parse(
            """
            [01:02.345]Second
            [00:02.5]First
            """
        )

        #expect(lines.map(\.text) == ["First", "Second"])
        #expect(abs((lines.first?.time ?? 0) - 2.5) < 0.0001)
        #expect(abs((lines.last?.time ?? 0) - 62.345) < 0.0001)
    }
}
