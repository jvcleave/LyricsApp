import Foundation

public struct FilenameMetadataParser: Sendable {
    private static let leadingTrackPattern = #"^\s*\d{1,3}\s*(?:[-–—.]\s*)+"#
    private static let noiseSuffixPattern = #"\s*[\(\[]\s*(?:official\s+audio|official\s+music\s+video|official\s+video|lyrics?|lyric\s+video|music\s+video|hd|4k)\s*[\)\]]\s*$"#
    private static let trailingVideoIDPattern = #"\s*\[[A-Za-z0-9_-]{11}\]\s*$"#
    private static let artistTitleSeparatorPattern = #"\s+[-–—]\s+"#
    private static let mediaExtensions: Set<String> = [
        "aac", "aif", "aiff", "avi", "caf", "flac", "m4a", "m4v", "mkv",
        "mov", "mp3", "mp4", "ogg", "opus", "quicktime", "wav", "webm",
    ]

    public init() {}

    public func parse(fileURL: URL) -> FilenameMetadata {
        var sourceURL = fileURL
        while Self.mediaExtensions.contains(sourceURL.pathExtension.lowercased()) {
            sourceURL.deletePathExtension()
        }

        var name = sourceURL.lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
        name = name.replacingOccurrences(
            of: Self.leadingTrackPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        var previousName: String
        repeat {
            previousName = name
            name = name.replacingOccurrences(
                of: Self.trailingVideoIDPattern,
                with: "",
                options: .regularExpression
            )
            name = name.replacingOccurrences(
                of: Self.noiseSuffixPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        } while name != previousName

        name = name.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = name.range(
            of: Self.artistTitleSeparatorPattern,
            options: .regularExpression
        ) {
            let artist = String(name[..<separator.lowerBound])
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            let title = String(name[separator.upperBound...])
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            return FilenameMetadata(title: title, artist: artist)
        }
        return FilenameMetadata(title: name, artist: "")
    }
}
