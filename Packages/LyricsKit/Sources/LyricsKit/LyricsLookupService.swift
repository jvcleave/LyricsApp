import Foundation

public actor LyricsLookupService {
    private let lyricsService: LRCLibService
    private let ranker: LyricsMatchRanker
    private let fallbackBuilder: LyricsLookupFallbackBuilder
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
        fallbackBuilder = LyricsLookupFallbackBuilder()
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
            let lookupInputs = fallbackBuilder.inputs(startingWith: input)
            for (attemptIndex, lookupInput) in lookupInputs.enumerated() {
                if attemptIndex > 0 {
                    try await Task.sleep(for: .milliseconds(250))
                    try Task.checkCancellation()
                }

                if let exactMatch = try await lyricsService.exactMatch(input: lookupInput) {
                    return .match(exactMatch)
                }

                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                let searchResults = try await lyricsService.search(input: lookupInput)
                if searchResults.isEmpty {
                    continue
                }

                let rankedCandidates = ranker.ranked(
                    results: searchResults,
                    input: lookupInput
                )
                if let bestCandidate = rankedCandidates.first {
                    let runnerUp = rankedCandidates.dropFirst().first
                    if ranker.shouldSelectAutomatically(
                        best: bestCandidate,
                        runnerUp: runnerUp,
                        input: lookupInput
                    ) {
                        return .match(bestCandidate.result)
                    }
                    return .candidates(rankedCandidates)
                }
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
