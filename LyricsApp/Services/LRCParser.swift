import Foundation

struct LRCParser: Sendable {
    private struct ParsedLine {
        let sourceOrder: Int
        let time: TimeInterval
        let text: String
    }

    private static let timestampExpression = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
    )

    func parse(_ lyrics: String) -> [TimedLyricLine] {
        var parsedLines: [ParsedLine] = []
        var sourceOrder = 0

        for rawLine in lyrics.components(separatedBy: .newlines) {
            let range = NSRange(rawLine.startIndex..., in: rawLine)
            let matches = Self.timestampExpression.matches(in: rawLine, range: range)
            guard let finalMatch = matches.last,
                  let finalRange = Range(finalMatch.range, in: rawLine)
            else {
                continue
            }

            let text = String(rawLine[finalRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)

            for match in matches {
                guard let time = timeInterval(from: match, in: rawLine) else { continue }
                parsedLines.append(
                    ParsedLine(sourceOrder: sourceOrder, time: time, text: text)
                )
                sourceOrder += 1
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

    private func timeInterval(
        from match: NSTextCheckingResult,
        in line: String
    ) -> TimeInterval? {
        guard let minuteRange = Range(match.range(at: 1), in: line),
              let secondRange = Range(match.range(at: 2), in: line),
              let minutes = Double(line[minuteRange]),
              let seconds = Double(line[secondRange]),
              seconds < 60
        else {
            return nil
        }

        var fraction = 0.0
        if match.range(at: 3).location != NSNotFound,
           let fractionRange = Range(match.range(at: 3), in: line) {
            let digits = String(line[fractionRange])
            if let value = Double(digits) {
                fraction = value / pow(10, Double(digits.count))
            }
        }

        return minutes * 60 + seconds + fraction
    }
}
