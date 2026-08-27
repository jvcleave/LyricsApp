import Foundation

struct FilenameMetadataParser: Sendable {
    private static let leadingTrackPattern = #"^\s*\d{1,3}\s*(?:[-–—.]\s*)+"#
    private static let noiseSuffixPattern = #"\s*[\(\[]\s*(?:official\s+audio|official\s+video|lyrics?|lyric\s+video|music\s+video|hd|4k)\s*[\)\]]\s*$"#
    private static let artistTitleSeparatorPattern = #"\s+[-–—]\s+"#

    func parse(fileURL: URL) -> FilenameMetadata {
        var name = fileURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
        name = replacingMatches(
            in: name,
            pattern: Self.leadingTrackPattern,
            with: ""
        )

        var previousName: String
        repeat {
            previousName = name
            name = replacingMatches(
                in: name,
                pattern: Self.noiseSuffixPattern,
                with: ""
            )
        } while name != previousName

        name = collapsedWhitespace(name)
        guard let separator = name.range(
            of: Self.artistTitleSeparatorPattern,
            options: .regularExpression
        ) else {
            return FilenameMetadata(title: name, artist: "")
        }

        let artist = collapsedWhitespace(String(name[..<separator.lowerBound]))
        let title = collapsedWhitespace(String(name[separator.upperBound...]))
        return FilenameMetadata(title: title, artist: artist)
    }

    private func replacingMatches(
        in value: String,
        pattern: String,
        with replacement: String
    ) -> String {
        value.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private func collapsedWhitespace(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
