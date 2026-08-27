import Foundation

struct LyricsResult: Codable, Identifiable, Sendable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double?
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
}

struct LyricsCandidateDisplayItem: Identifiable, Sendable {
    let id: Int
    let title: String
    let artist: String
    let album: String?
    let durationText: String
    let matchDetail: String?
}

struct LyricsDisplayContent: Sendable {
    enum Body: Sendable {
        case instrumental
        case timed([TimedLyricLine])
        case plain(String)
        case unavailable
    }

    let title: String
    let artist: String
    let album: String?
    let body: Body
}
