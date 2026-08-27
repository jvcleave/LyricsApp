import Foundation

public struct LRCParser: Sendable {
    private struct ParsedLine {
        let sourceOrder: Int
        let time: TimeInterval
        let text: String
    }

    private static let timestampExpression = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
    )

    public init() {}

    public func parse(_ lyrics: String) -> [TimedLyricLine] {
        var parsedLines: [ParsedLine] = []
        var sourceOrder = 0

        for rawLine in lyrics.components(separatedBy: .newlines) {
            let range = NSRange(rawLine.startIndex..., in: rawLine)
            let matches = Self.timestampExpression.matches(in: rawLine, range: range)
            if let finalMatch = matches.last,
               let finalRange = Range(finalMatch.range, in: rawLine) {
                let text = String(rawLine[finalRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)

                for match in matches {
                    if let minuteRange = Range(match.range(at: 1), in: rawLine),
                       let secondRange = Range(match.range(at: 2), in: rawLine),
                       let minutes = Double(rawLine[minuteRange]),
                       let seconds = Double(rawLine[secondRange]),
                       seconds < 60 {
                        var fraction = 0.0
                        if match.range(at: 3).location != NSNotFound,
                           let fractionRange = Range(match.range(at: 3), in: rawLine) {
                            let digits = String(rawLine[fractionRange])
                            if let value = Double(digits) {
                                fraction = value / pow(10, Double(digits.count))
                            }
                        }
                        parsedLines.append(ParsedLine(
                            sourceOrder: sourceOrder,
                            time: minutes * 60 + seconds + fraction,
                            text: text
                        ))
                        sourceOrder += 1
                    }
                }
            }
        }

        return parsedLines
            .sorted {
                if $0.time == $1.time {
                    return $0.sourceOrder < $1.sourceOrder
                }
                return $0.time < $1.time
            }
            .enumerated()
            .map { index, line in
                TimedLyricLine(id: index, time: line.time, text: line.text)
            }
    }
}
