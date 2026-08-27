import AVFoundation
import Foundation

public enum AudioMetadataReaderError: LocalizedError {
    case unreadableFile

    public var errorDescription: String? {
        switch self {
            case .unreadableFile:
                return "The selected audio file could not be read."
        }
    }
}

public struct AudioMetadataReader: Sendable {
    public init() {}

    public func read(fileURL: URL) async throws -> SongMetadata {
        let accessedSecurityScopedResource = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: fileURL)

        do {
            async let loadedDuration = asset.load(.duration)
            async let loadedMetadata = asset.load(.commonMetadata)
            let (duration, metadata) = try await (loadedDuration, loadedMetadata)

            var title = ""
            var artist = ""
            var album = ""
            for metadataItem in metadata {
                if let value = try? await metadataItem.load(.stringValue) {
                    let cleanedValue = value.replacingOccurrences(of: "\0", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if metadataItem.commonKey == .commonKeyTitle,
                       title.isEmpty,
                       cleanedValue.isEmpty == false {
                        title = cleanedValue
                    } else if metadataItem.commonKey == .commonKeyArtist,
                              artist.isEmpty,
                              cleanedValue.isEmpty == false {
                        artist = cleanedValue
                    } else if metadataItem.commonKey == .commonKeyAlbumName,
                              album.isEmpty,
                              cleanedValue.isEmpty == false {
                        album = cleanedValue
                    }
                }
            }
            let durationSeconds = duration.seconds
            let usableDuration = durationSeconds.isFinite && durationSeconds > 0
                ? durationSeconds
                : nil

            return SongMetadata(
                fileURL: fileURL,
                title: title,
                artist: artist,
                album: album,
                duration: usableDuration
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AudioMetadataReaderError.unreadableFile
        }
    }
}
