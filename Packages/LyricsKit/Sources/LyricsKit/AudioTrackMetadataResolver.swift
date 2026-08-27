import Foundation

public struct AudioTrackMetadataResolver: Sendable {
    private let metadataReader: AudioMetadataReader
    private let filenameParser: FilenameMetadataParser

    public init(
        metadataReader: AudioMetadataReader = AudioMetadataReader(),
        filenameParser: FilenameMetadataParser = FilenameMetadataParser()
    ) {
        self.metadataReader = metadataReader
        self.filenameParser = filenameParser
    }

    public func resolve(fileURL: URL) async throws -> SongMetadata {
        let embeddedMetadata = try await metadataReader.read(fileURL: fileURL)
        let filenameMetadata = filenameParser.parse(fileURL: fileURL)
        let title = embeddedMetadata.title.isEmpty
            ? filenameMetadata.title
            : embeddedMetadata.title
        let artist = embeddedMetadata.artist.isEmpty
            ? filenameMetadata.artist
            : embeddedMetadata.artist
        return SongMetadata(
            fileURL: fileURL,
            title: title,
            artist: artist,
            album: embeddedMetadata.album,
            duration: embeddedMetadata.duration
        )
    }
}
