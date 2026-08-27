import Foundation

public struct LyricsContentResolver: Sendable {
    private let lrcParser: LRCParser

    public init(lrcParser: LRCParser = LRCParser()) {
        self.lrcParser = lrcParser
    }

    public func resolve(result: LyricsResult) -> ResolvedLyricsContent {
        if result.instrumental {
            return .instrumental
        }
        if let synchronizedLyrics = useful(result.syncedLyrics) {
            let lines = lrcParser.parse(synchronizedLyrics)
            if lines.isEmpty == false {
                return .synchronized(
                    originalText: synchronizedLyrics,
                    lines: lines
                )
            }
        }
        if let plainLyrics = useful(result.plainLyrics) {
            let lines = plainLyrics.components(separatedBy: .newlines).compactMap { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedLine.isEmpty ? nil : trimmedLine
            }
            if lines.isEmpty == false {
                return .plain(originalText: plainLyrics, lines: lines)
            }
        }
        return .unavailable
    }

    private func useful(_ value: String?) -> String? {
        if let value {
            let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedValue.isEmpty == false {
                return cleanedValue
            }
        }
        return nil
    }
}
