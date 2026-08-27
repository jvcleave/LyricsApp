import AVFoundation
import Foundation

enum AudioMetadataReaderError: LocalizedError {
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "The selected audio file could not be read."
        }
    }
}

struct AudioMetadataReader: Sendable {
    func read(from fileURL: URL) async throws -> SongMetadata {
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

            return SongMetadata(
                fileURL: fileURL,
                title: await stringValue(for: .commonKeyTitle, in: metadata) ?? "",
                artist: await stringValue(for: .commonKeyArtist, in: metadata) ?? "",
                album: await stringValue(for: .commonKeyAlbumName, in: metadata) ?? "",
                duration: usableDuration(duration.seconds)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AudioMetadataReaderError.unreadableFile
        }
    }

    private func stringValue(
        for commonKey: AVMetadataKey,
        in metadata: [AVMetadataItem]
    ) async -> String? {
        for item in metadata where item.commonKey == commonKey {
            guard let value = try? await item.load(.stringValue) else { continue }
            let cleaned = value
                .replacingOccurrences(of: "\0", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return nil
    }

    private func usableDuration(_ seconds: Double) -> TimeInterval? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }
}
