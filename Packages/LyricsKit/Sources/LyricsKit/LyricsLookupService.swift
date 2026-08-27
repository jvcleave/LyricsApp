import Foundation

public actor LyricsLookupService {
    private let lyricsService: LRCLibService
    private let ranker: LyricsMatchRanker
    private var requestNotBefore: Date?

    public init(
        clientIdentifier: String = "LyricsKit/1.0 (https://github.com/jvcleave/LyricsApp)",
        session: URLSession = .shared,
        ranker: LyricsMatchRanker = LyricsMatchRanker()
    ) {
        lyricsService = LRCLibService(
            session: session,
            clientIdentifier: clientIdentifier
        )
        self.ranker = ranker
    }

    public func findLyrics(input: LyricsMatchInput) async throws -> LyricsLookupOutcome {
        if let requestNotBefore {
            let remainingDelay = requestNotBefore.timeIntervalSinceNow
            if remainingDelay > 0 {
                throw LRCLibServiceError.rateLimited(retryAfter: remainingDelay)
            }
            self.requestNotBefore = nil
        }

        do {
            if let exactMatch = try await lyricsService.exactMatch(input: input) {
                return .match(exactMatch)
            }

            try await Task.sleep(for: .milliseconds(250))
            try Task.checkCancellation()
            let searchResults = try await lyricsService.search(input: input)
            if searchResults.isEmpty {
                return .notFound
            }

            let rankedCandidates = ranker.ranked(
                results: searchResults,
                input: input
            )
            if let bestCandidate = rankedCandidates.first {
                let runnerUp = rankedCandidates.dropFirst().first
                if ranker.shouldSelectAutomatically(
                    best: bestCandidate,
                    runnerUp: runnerUp,
                    input: input
                ) {
                    return .match(bestCandidate.result)
                }
                return .candidates(rankedCandidates)
            }
            return .notFound
        } catch let error as LRCLibServiceError {
            if case let .rateLimited(retryAfter) = error,
               let retryAfter,
               retryAfter > 0 {
                requestNotBefore = Date().addingTimeInterval(retryAfter)
            }
            throw error
        }
    }
}
