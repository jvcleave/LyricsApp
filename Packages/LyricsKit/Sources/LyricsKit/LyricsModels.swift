import Foundation

public enum LyricsProvider: String, Codable, Equatable, Sendable {
    case lrclib
    case lrcmux

    public var displayName: String {
        switch self {
            case .lrclib:
                return "LRCLIB"
            case .lrcmux:
                return "LRCMÜX"
        }
    }
}

public struct LyricsSource: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let url: URL?

    public init(
        id: String,
        name: String,
        url: URL?
    ) {
        self.id = id
        self.name = name
        self.url = url
    }
}

public struct LyricsResult: Codable, Identifiable, Sendable {
    public let id: String
    public let provider: LyricsProvider
    public let upstreamSource: LyricsSource?
    public let trackName: String
    public let artistName: String
    public let albumName: String?
    public let duration: Double?
    public let instrumental: Bool
    public let plainLyrics: String?
    public let syncedLyrics: String?

    public init(
        id: String,
        provider: LyricsProvider,
        upstreamSource: LyricsSource?,
        trackName: String,
        artistName: String,
        albumName: String?,
        duration: Double?,
        instrumental: Bool,
        plainLyrics: String?,
        syncedLyrics: String?
    ) {
        self.id = id
        self.provider = provider
        self.upstreamSource = upstreamSource
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.instrumental = instrumental
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
    }
}

public struct SongMetadata: Sendable {
    public let fileURL: URL
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval?

    public init(
        fileURL: URL,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval?
    ) {
        self.fileURL = fileURL
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}

public struct FilenameMetadata: Equatable, Sendable {
    public let title: String
    public let artist: String

    public init(title: String, artist: String) {
        self.title = title
        self.artist = artist
    }
}

public struct TimedLyricLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let time: TimeInterval
    public let text: String

    public init(id: Int, time: TimeInterval, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}

public struct LyricsMatchInput: Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval?

    public init(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval?
    ) {
        self.title = title.precomposedStringWithCanonicalMapping
        self.artist = artist.precomposedStringWithCanonicalMapping
        self.album = album.precomposedStringWithCanonicalMapping
        self.duration = duration
    }
}

public struct RankedLyricsCandidate: Sendable {
    public let result: LyricsResult
    public let score: Int
    public let durationDifference: TimeInterval?
    public let exactTitle: Bool
    public let exactArtist: Bool

    public init(
        result: LyricsResult,
        score: Int,
        durationDifference: TimeInterval?,
        exactTitle: Bool,
        exactArtist: Bool
    ) {
        self.result = result
        self.score = score
        self.durationDifference = durationDifference
        self.exactTitle = exactTitle
        self.exactArtist = exactArtist
    }
}

public enum LyricsLookupOutcome: Sendable {
    case match(LyricsResult)
    case candidates([RankedLyricsCandidate])
    case notFound
}

public enum LyricsContentRequirement: Equatable, Sendable {
    case any
    case synchronized
}

public enum LyricsLookupError: LocalizedError, Sendable {
    case invalidRequest
    case temporarilyUnavailable(retryAfter: TimeInterval?)

    public var errorDescription: String? {
        switch self {
            case .invalidRequest:
                return "The lyrics request could not be created."
            case let .temporarilyUnavailable(retryAfter):
                if let retryAfter {
                    return "Lyrics providers are temporarily unavailable. Please try again in \(Int(ceil(retryAfter))) seconds."
                }
                return "Lyrics providers are temporarily unavailable. Please try again shortly."
        }
    }
}

public enum ResolvedLyricsContent: Sendable {
    case synchronized(originalText: String, lines: [TimedLyricLine])
    case plain(originalText: String, lines: [String])
    case instrumental
    case unavailable
}
