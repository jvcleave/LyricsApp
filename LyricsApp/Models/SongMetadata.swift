import Foundation

struct SongMetadata: Sendable {
    let fileURL: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?
}

struct FilenameMetadata: Equatable, Sendable {
    let title: String
    let artist: String
}
