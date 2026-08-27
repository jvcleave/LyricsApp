import Foundation
import LyricsKit
import Observation
import OSLog

enum LyricsFinderPhase: Sendable {
    case idle
    case importing
    case ready
    case searching
    case candidates([LyricsCandidateDisplayItem])
    case found(LyricsDisplayContent)
    case notFound
    case failed(String)
}

@MainActor
@Observable
final class LyricsFinderViewModel {
    var title = "" {
        didSet { metadataDidChange(from: oldValue, to: title) }
    }
    var artist = "" {
        didSet { metadataDidChange(from: oldValue, to: artist) }
    }
    var album = "" {
        didSet { metadataDidChange(from: oldValue, to: album) }
    }
    var durationText = "" {
        didSet { metadataDidChange(from: oldValue, to: durationText) }
    }

    private(set) var fileName: String?
    private(set) var phase: LyricsFinderPhase = .idle

    var hasImportedFile: Bool { fileName != nil }
    var isBusy: Bool {
        switch phase {
        case .importing, .searching:
            true
        default:
            false
        }
    }
    var canFindLyrics: Bool {
        hasImportedFile
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBusy
    }

    @ObservationIgnored private let metadataReader: AudioMetadataReader
    @ObservationIgnored private let filenameParser: FilenameMetadataParser
    @ObservationIgnored private let lookupService: LyricsLookupService
    @ObservationIgnored private let lrcParser: LRCParser
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var candidatesByID: [Int: LyricsResult] = [:]
    @ObservationIgnored private var isApplyingImportedMetadata = false

    private static let logger = Logger(
        subsystem: "com.jvclabs.LyricsApp",
        category: "LyricsFinder"
    )

    init(
        metadataReader: AudioMetadataReader = AudioMetadataReader(),
        filenameParser: FilenameMetadataParser = FilenameMetadataParser(),
        lookupService: LyricsLookupService = LyricsLookupService(),
        lrcParser: LRCParser = LRCParser()
    ) {
        self.metadataReader = metadataReader
        self.filenameParser = filenameParser
        self.lookupService = lookupService
        self.lrcParser = lrcParser
    }

    deinit {
        operationTask?.cancel()
    }

    func importAudioFile(at fileURL: URL) {
        operationTask?.cancel()
        candidatesByID.removeAll()
        phase = .importing

        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let embedded = try await metadataReader.read(fileURL: fileURL)
                try Task.checkCancellation()
                let guessed = filenameParser.parse(fileURL: fileURL)
                applyImportedMetadata(embedded, guessed: guessed)
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(error.localizedDescription)
                Self.logger.error("Audio import failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func presentImportError(_ error: Error) {
        phase = .failed("The audio file could not be imported: \(error.localizedDescription)")
    }

    func findLyrics() {
        let input: LyricsMatchInput
        do {
            input = try makeMatchInput()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        operationTask?.cancel()
        candidatesByID.removeAll()
        phase = .searching

        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                Self.logger.debug("Trying LRCLIB lookup with bounded title fallbacks")
                let outcome = try await lookupService.findLyrics(input: input)
                try Task.checkCancellation()
                switch outcome {
                    case let .match(result):
                        Self.logger.debug("Found LRCLIB match: \(result.artistName, privacy: .public) - \(result.trackName, privacy: .public)")
                        showLyrics(result)
                    case let .candidates(rankedCandidates):
                        applyRankedCandidates(rankedCandidates)
                    case .notFound:
                        phase = .notFound
                }
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(error.localizedDescription)
                Self.logger.error("Lyrics search failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func selectCandidate(id: Int) {
        guard let result = candidatesByID[id] else { return }
        showLyrics(result)
    }

    private func applyImportedMetadata(
        _ embedded: SongMetadata,
        guessed: FilenameMetadata
    ) {
        isApplyingImportedMetadata = true
        fileName = embedded.fileURL.lastPathComponent
        title = useful(embedded.title) ?? guessed.title
        artist = useful(embedded.artist) ?? guessed.artist
        album = useful(embedded.album) ?? ""
        durationText = embedded.duration.map { String(format: "%.1f", $0) } ?? ""
        isApplyingImportedMetadata = false
        phase = .ready

        Self.logger.debug("Imported: \(embedded.fileURL.lastPathComponent, privacy: .public)")
        Self.logger.debug("Detected title: \(self.title, privacy: .public)")
        Self.logger.debug("Detected artist: \(self.artist, privacy: .public)")
        Self.logger.debug("Detected album: \(self.album, privacy: .public)")
        Self.logger.debug("Detected duration: \(self.durationText, privacy: .public)")
    }

    private func applyRankedCandidates(_ rankedCandidates: [RankedLyricsCandidate]) {
        guard rankedCandidates.isEmpty == false else {
            phase = .notFound
            return
        }

        candidatesByID = Dictionary(
            uniqueKeysWithValues: rankedCandidates.map { ($0.result.id, $0.result) }
        )
        Self.logger.debug("LRCLIB lookup found \(rankedCandidates.count) candidates")
        phase = .candidates(rankedCandidates.map(makeCandidateDisplayItem))
    }

    private func showLyrics(_ result: LyricsResult) {
        candidatesByID.removeAll()

        let body: LyricsDisplayContent.Body
        if result.instrumental {
            body = .instrumental
        } else if let synced = useful(result.syncedLyrics) {
            let lines = lrcParser.parse(synced)
            body = lines.isEmpty ? .plain(synced) : .timed(lines)
        } else if let plain = useful(result.plainLyrics) {
            body = .plain(plain)
        } else {
            body = .unavailable
        }

        phase = .found(
            LyricsDisplayContent(
                title: result.trackName,
                artist: result.artistName,
                album: useful(result.albumName),
                body: body
            )
        )
    }

    private func makeCandidateDisplayItem(
        _ ranked: RankedLyricsCandidate
    ) -> LyricsCandidateDisplayItem {
        let durationText: String
        if let duration = ranked.result.duration {
            durationText = Self.durationFormatter.string(from: duration) ?? ""
        } else {
            durationText = "Duration unknown"
        }

        let matchDetail: String?
        if let difference = ranked.durationDifference {
            matchDetail = "\(difference.formatted(.number.precision(.fractionLength(1))))s from file duration"
        } else {
            matchDetail = nil
        }

        return LyricsCandidateDisplayItem(
            id: ranked.result.id,
            title: ranked.result.trackName,
            artist: ranked.result.artistName,
            album: useful(ranked.result.albumName),
            durationText: durationText,
            matchDetail: matchDetail
        )
    }

    private func makeMatchInput() throws -> LyricsMatchInput {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            throw ValidationError.missingTitle
        }

        let cleanedDuration = durationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration: TimeInterval?
        if cleanedDuration.isEmpty {
            duration = nil
        } else if let parsed = TimeInterval(cleanedDuration), parsed.isFinite, parsed > 0 {
            duration = parsed
        } else {
            throw ValidationError.invalidDuration
        }

        return LyricsMatchInput(
            title: cleanedTitle,
            artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
            album: album.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration
        )
    }

    private func metadataDidChange(from oldValue: String, to newValue: String) {
        guard !isApplyingImportedMetadata, oldValue != newValue, hasImportedFile else {
            return
        }
        candidatesByID.removeAll()
        phase = .ready
    }

    private func useful(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
}

private enum ValidationError: LocalizedError {
    case missingTitle
    case invalidDuration

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            "Enter a track title before searching."
        case .invalidDuration:
            "Duration must be a positive number of seconds."
        }
    }
}
