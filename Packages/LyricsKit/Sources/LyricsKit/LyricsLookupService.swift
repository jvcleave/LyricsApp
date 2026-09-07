import Foundation

public actor LyricsLookupService {
    private struct TemporaryFailure {
        let retryAfter: TimeInterval?
    }

    private let lrclibService: LRCLibService
    private let lrcmuxService: LRCMuxService
    private let ranker: LyricsMatchRanker
    private let fallbackBuilder: LyricsLookupFallbackBuilder
    private let contentResolver: LyricsContentResolver
    private var lrclibRequestNotBefore: Date?
    private var lrcmuxRequestNotBefore: Date?

    public init(
        clientIdentifier: String = "LyricsKit/1.0 (https://github.com/jvcleave/LyricsApp)",
        session: URLSession = .shared,
        ranker: LyricsMatchRanker = LyricsMatchRanker()
    ) {
        lrclibService = LRCLibService(
            session: session,
            clientIdentifier: clientIdentifier
        )
        lrcmuxService = LRCMuxService(
            session: session,
            clientIdentifier: clientIdentifier
        )
        self.ranker = ranker
        fallbackBuilder = LyricsLookupFallbackBuilder()
        contentResolver = LyricsContentResolver()
    }

    init(
        lrclibService: LRCLibService,
        lrcmuxService: LRCMuxService,
        ranker: LyricsMatchRanker = LyricsMatchRanker()
    ) {
        self.lrclibService = lrclibService
        self.lrcmuxService = lrcmuxService
        self.ranker = ranker
        fallbackBuilder = LyricsLookupFallbackBuilder()
        contentResolver = LyricsContentResolver()
    }

    public func findLyrics(
        input: LyricsMatchInput,
        requirement: LyricsContentRequirement
    ) async throws -> LyricsLookupOutcome {
        if input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LyricsLookupError.invalidRequest
        }

        var temporaryFailures: [TemporaryFailure] = []
        if let retryAfter = remainingCooldown(requestNotBefore: lrclibRequestNotBefore) {
            temporaryFailures.append(TemporaryFailure(retryAfter: retryAfter))
        } else {
            lrclibRequestNotBefore = nil
            do {
                let outcome = try await findLRCLibLyrics(
                    input: input,
                    requirement: requirement
                )
                switch outcome {
                    case .match, .candidates:
                        return outcome
                    case .notFound:
                        break
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as LRCLibServiceError {
                switch error {
                    case .invalidRequest:
                        throw LyricsLookupError.invalidRequest
                    case let .rateLimited(retryAfter):
                        if let retryAfter, retryAfter > 0 {
                            lrclibRequestNotBefore = Date().addingTimeInterval(retryAfter)
                        }
                        temporaryFailures.append(TemporaryFailure(retryAfter: retryAfter))
                    case .network, .decoding:
                        temporaryFailures.append(TemporaryFailure(retryAfter: nil))
                    case let .server(statusCode, _):
                        if statusCode >= 500 || statusCode == 0 {
                            temporaryFailures.append(TemporaryFailure(retryAfter: nil))
                        } else {
                            throw LyricsLookupError.invalidRequest
                        }
                }
            }
        }

        try Task.checkCancellation()

        if input.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if temporaryFailures.isEmpty {
                return .notFound
            }
            throw temporaryUnavailableError(failures: temporaryFailures)
        }

        if let retryAfter = remainingCooldown(requestNotBefore: lrcmuxRequestNotBefore) {
            temporaryFailures.append(TemporaryFailure(retryAfter: retryAfter))
            throw temporaryUnavailableError(failures: temporaryFailures)
        }
        lrcmuxRequestNotBefore = nil

        do {
            if let result = try await lrcmuxService.lyrics(
                input: input,
                requirement: requirement
            ), resultSatisfiesRequirement(result: result, requirement: requirement) {
                return .match(result)
            }
            if temporaryFailures.isEmpty {
                return .notFound
            }
            throw temporaryUnavailableError(failures: temporaryFailures)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LyricsLookupError {
            throw error
        } catch let error as LRCMuxServiceError {
            switch error {
                case .invalidRequest:
                    throw LyricsLookupError.invalidRequest
                case let .rateLimited(retryAfter):
                    if let retryAfter, retryAfter > 0 {
                        lrcmuxRequestNotBefore = Date().addingTimeInterval(retryAfter)
                    }
                    temporaryFailures.append(TemporaryFailure(retryAfter: retryAfter))
                case .network, .decoding:
                    temporaryFailures.append(TemporaryFailure(retryAfter: nil))
                case let .server(statusCode, _):
                    if statusCode >= 500 || statusCode == 0 {
                        temporaryFailures.append(TemporaryFailure(retryAfter: nil))
                    } else {
                        throw LyricsLookupError.invalidRequest
                    }
            }
            throw temporaryUnavailableError(failures: temporaryFailures)
        }
    }

    private func findLRCLibLyrics(
        input: LyricsMatchInput,
        requirement: LyricsContentRequirement
    ) async throws -> LyricsLookupOutcome {
        let lookupInputs = fallbackBuilder.inputs(startingWith: input)
        for (attemptIndex, lookupInput) in lookupInputs.enumerated() {
            if attemptIndex > 0 {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
            }

            if let exactMatch = try await lrclibService.exactMatch(input: lookupInput),
               resultSatisfiesRequirement(result: exactMatch, requirement: requirement) {
                return .match(exactMatch)
            }

            try await Task.sleep(for: .milliseconds(250))
            try Task.checkCancellation()
            let searchResults = try await lrclibService.search(input: lookupInput)
            let usableResults = searchResults.filter { result in
                resultSatisfiesRequirement(result: result, requirement: requirement)
            }
            if usableResults.isEmpty {
                continue
            }

            let rankedCandidates = ranker.ranked(
                results: usableResults,
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
    }

    private func resultSatisfiesRequirement(
        result: LyricsResult,
        requirement: LyricsContentRequirement
    ) -> Bool {
        let resolvedContent = contentResolver.resolve(result: result)
        switch resolvedContent {
            case .synchronized, .instrumental:
                return true
            case .plain:
                switch requirement {
                    case .any:
                        return true
                    case .synchronized:
                        return false
                }
            case .unavailable:
                return false
        }
    }

    private func remainingCooldown(requestNotBefore: Date?) -> TimeInterval? {
        if let requestNotBefore {
            let remainingDelay = requestNotBefore.timeIntervalSinceNow
            if remainingDelay > 0 {
                return remainingDelay
            }
        }
        return nil
    }

    private func temporaryUnavailableError(failures: [TemporaryFailure]) -> LyricsLookupError {
        if failures.contains(where: { $0.retryAfter == nil }) {
            return .temporarilyUnavailable(retryAfter: nil)
        }
        let retryAfter = failures.compactMap(\.retryAfter).min()
        return .temporarilyUnavailable(retryAfter: retryAfter)
    }
}
