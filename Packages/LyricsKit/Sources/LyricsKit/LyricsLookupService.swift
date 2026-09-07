import Foundation

public actor LyricsLookupService {
    private struct TemporaryFailure {
        let retryAfter: TimeInterval?
    }

    private enum ProviderAttemptResult {
        case outcome(LyricsLookupOutcome)
        case temporaryFailure(TemporaryFailure)
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
        requirement: LyricsContentRequirement,
        preferredProvider: LyricsProvider = .lrclib
    ) async throws -> LyricsLookupOutcome {
        if input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LyricsLookupError.invalidRequest
        }

        let providerOrder: [LyricsProvider]
        switch preferredProvider {
            case .lrclib:
                providerOrder = [.lrclib, .lrcmux]
            case .lrcmux:
                providerOrder = [.lrcmux, .lrclib]
        }

        var temporaryFailures: [TemporaryFailure] = []
        for provider in providerOrder {
            try Task.checkCancellation()
            let attemptResult: ProviderAttemptResult
            switch provider {
                case .lrclib:
                    attemptResult = try await attemptLRCLibLookup(
                        input: input,
                        requirement: requirement
                    )
                case .lrcmux:
                    attemptResult = try await attemptLRCMuxLookup(
                        input: input,
                        requirement: requirement
                    )
            }

            switch attemptResult {
                case let .outcome(outcome):
                    switch outcome {
                        case .match, .candidates:
                            return outcome
                        case .notFound:
                            break
                    }
                case let .temporaryFailure(failure):
                    temporaryFailures.append(failure)
            }
        }

        if temporaryFailures.isEmpty {
            return .notFound
        }
        throw temporaryUnavailableError(failures: temporaryFailures)
    }

    private func attemptLRCLibLookup(
        input: LyricsMatchInput,
        requirement: LyricsContentRequirement
    ) async throws -> ProviderAttemptResult {
        if let retryAfter = remainingCooldown(requestNotBefore: lrclibRequestNotBefore) {
            return .temporaryFailure(TemporaryFailure(retryAfter: retryAfter))
        }
        lrclibRequestNotBefore = nil

        do {
            let outcome = try await findLRCLibLyrics(
                input: input,
                requirement: requirement
            )
            return .outcome(outcome)
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
                    return .temporaryFailure(TemporaryFailure(retryAfter: retryAfter))
                case .network, .decoding:
                    return .temporaryFailure(TemporaryFailure(retryAfter: nil))
                case let .server(statusCode, _):
                    if statusCode >= 500 || statusCode == 0 {
                        return .temporaryFailure(TemporaryFailure(retryAfter: nil))
                    }
                    throw LyricsLookupError.invalidRequest
            }
        }
    }

    private func attemptLRCMuxLookup(
        input: LyricsMatchInput,
        requirement: LyricsContentRequirement
    ) async throws -> ProviderAttemptResult {
        if input.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .outcome(.notFound)
        }
        if let retryAfter = remainingCooldown(requestNotBefore: lrcmuxRequestNotBefore) {
            return .temporaryFailure(TemporaryFailure(retryAfter: retryAfter))
        }
        lrcmuxRequestNotBefore = nil

        do {
            if let result = try await lrcmuxService.lyrics(
                input: input,
                requirement: requirement
            ), resultSatisfiesRequirement(result: result, requirement: requirement) {
                return .outcome(.match(result))
            }
            return .outcome(.notFound)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LRCMuxServiceError {
            switch error {
                case .invalidRequest:
                    throw LyricsLookupError.invalidRequest
                case let .rateLimited(retryAfter):
                    if let retryAfter, retryAfter > 0 {
                        lrcmuxRequestNotBefore = Date().addingTimeInterval(retryAfter)
                    }
                    return .temporaryFailure(TemporaryFailure(retryAfter: retryAfter))
                case .network, .decoding:
                    return .temporaryFailure(TemporaryFailure(retryAfter: nil))
                case let .server(statusCode, _):
                    if statusCode >= 500 || statusCode == 0 {
                        return .temporaryFailure(TemporaryFailure(retryAfter: nil))
                    }
                    throw LyricsLookupError.invalidRequest
            }
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
