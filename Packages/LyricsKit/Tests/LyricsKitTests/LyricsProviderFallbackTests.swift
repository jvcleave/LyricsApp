import Foundation
@testable import LyricsKit
import Testing

private final class LyricsURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct LyricsProviderFallbackTests {
    @Test func lrcmuxBuildsIndependentSynchronizedRequestAndDecodesResult() async throws {
        let session = makeSession()
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }

        LyricsURLProtocol.handler = { request in
            let requestURL = try #require(request.url)
            let components = try #require(
                URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
            )
            let queryItems = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map { queryItem in
                    (queryItem.name, queryItem.value ?? "")
                }
            )
            #expect(components.path == "/get")
            #expect(queryItems["artist"] == "Artist")
            #expect(queryItems["title"] == "Song")
            #expect(queryItems["album"] == "Album")
            #expect(queryItems["duration"] == "181")
            #expect(queryItems["level"] == "line")
            #expect(queryItems["strict"] == "true")
            #expect(queryItems["format"] == "json")
            #expect(queryItems["sources"] == "!lrclib")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "LyricsKitTests/1.0")
            return response(
                request: request,
                statusCode: 200,
                body: lrcmuxTimedJSON
            )
        }

        let service = LRCMuxService(
            baseURL: URL(string: "https://lrcmux.test")!,
            session: session,
            clientIdentifier: "LyricsKitTests/1.0"
        )
        let result = try #require(
            try await service.lyrics(
                input: matchInput,
                requirement: .synchronized
            )
        )

        #expect(result.id == "lrcmux:ytmusic:TEST123")
        #expect(result.provider == .lrcmux)
        #expect(result.upstreamSource?.id == "ytmusic")
        #expect(result.syncedLyrics == "[00:01.250]First line\n[00:03.500]Second line")
        #expect(result.plainLyrics == "First line\nSecond line")
    }

    @Test func lrclibTimedResultBypassesLrcmux() async throws {
        let session = makeSession()
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }
        var lrcmuxRequestCount = 0
        LyricsURLProtocol.handler = { request in
            if request.url?.host == "lrcmux.test" {
                lrcmuxRequestCount += 1
                return response(request: request, statusCode: 500)
            }
            return response(
                request: request,
                statusCode: 200,
                body: lrclibTimedJSON
            )
        }

        let lookupService = makeLookupService(session: session)
        let outcome = try await lookupService.findLyrics(
            input: matchInput,
            requirement: .synchronized
        )

        if case let .match(result) = outcome {
            #expect(result.id == "lrclib:42")
            #expect(result.provider == .lrclib)
        } else {
            Issue.record("Expected an LRCLIB match")
        }
        #expect(lrcmuxRequestCount == 0)
    }

    @Test func lrcmuxDecodesInstrumentalResponseWithoutLines() async throws {
        let session = makeSession()
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }
        LyricsURLProtocol.handler = { request in
            response(
                request: request,
                statusCode: 200,
                body: lrcmuxInstrumentalJSON
            )
        }

        let service = LRCMuxService(
            baseURL: URL(string: "https://lrcmux.test")!,
            session: session,
            clientIdentifier: "LyricsKitTests/1.0"
        )
        let result = try #require(
            try await service.lyrics(
                input: matchInput,
                requirement: .synchronized
            )
        )

        #expect(result.instrumental)
        #expect(result.plainLyrics == nil)
        #expect(result.syncedLyrics == nil)
    }

    @Test func lrcmuxExposesRetryAfter() async throws {
        let session = makeSession()
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }
        LyricsURLProtocol.handler = { request in
            response(
                request: request,
                statusCode: 429,
                headers: ["Retry-After": "75"]
            )
        }

        let service = LRCMuxService(
            baseURL: URL(string: "https://lrcmux.test")!,
            session: session,
            clientIdentifier: "LyricsKitTests/1.0"
        )
        do {
            _ = try await service.lyrics(
                input: matchInput,
                requirement: .synchronized
            )
            Issue.record("Expected rate limiting")
        } catch let error as LRCMuxServiceError {
            if case let .rateLimited(retryAfter) = error {
                #expect(retryAfter == 75)
            } else {
                Issue.record("Expected rate limiting")
            }
        }
    }

    @Test func plainLrclibResultOnlyFallsBackWhenSynchronizationIsRequired() async throws {
        let anySession = makeSession()
        defer { anySession.invalidateAndCancel() }
        var anyLrcmuxRequestCount = 0
        LyricsURLProtocol.handler = { request in
            if request.url?.host == "lrcmux.test" {
                anyLrcmuxRequestCount += 1
                return response(request: request, statusCode: 500)
            }
            return response(
                request: request,
                statusCode: 200,
                body: lrclibPlainJSON
            )
        }
        let anyLookupService = makeLookupService(session: anySession)
        let anyOutcome = try await anyLookupService.findLyrics(
            input: matchInput,
            requirement: .any
        )
        if case let .match(result) = anyOutcome {
            #expect(result.provider == .lrclib)
            #expect(result.plainLyrics == "Plain line")
        } else {
            Issue.record("Expected plain LRCLIB lyrics")
        }
        #expect(anyLrcmuxRequestCount == 0)

        anySession.invalidateAndCancel()
        let synchronizedSession = makeSession()
        defer {
            LyricsURLProtocol.handler = nil
            synchronizedSession.invalidateAndCancel()
        }
        var synchronizedLrcmuxRequestCount = 0
        LyricsURLProtocol.handler = { request in
            switch (request.url?.host, request.url?.path) {
                case ("lrclib.test", "/api/get"):
                    return response(
                        request: request,
                        statusCode: 200,
                        body: lrclibPlainJSON
                    )
                case ("lrclib.test", "/api/search"):
                    return response(request: request, statusCode: 200, body: "[]")
                case ("lrcmux.test", "/get"):
                    synchronizedLrcmuxRequestCount += 1
                    return response(
                        request: request,
                        statusCode: 200,
                        body: lrcmuxTimedJSON
                    )
                default:
                    return response(request: request, statusCode: 500)
            }
        }
        let synchronizedLookupService = makeLookupService(session: synchronizedSession)
        let synchronizedOutcome = try await synchronizedLookupService.findLyrics(
            input: matchInput,
            requirement: .synchronized
        )
        if case let .match(result) = synchronizedOutcome {
            #expect(result.provider == .lrcmux)
        } else {
            Issue.record("Expected synchronized LRCMÜX fallback")
        }
        #expect(synchronizedLrcmuxRequestCount == 1)
    }

    @Test func definitiveMissFromBothProvidersReturnsNotFound() async throws {
        let session = makeSession()
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }
        LyricsURLProtocol.handler = { request in
            if request.url?.path == "/api/search" {
                return response(request: request, statusCode: 200, body: "[]")
            }
            return response(request: request, statusCode: 404)
        }

        let lookupService = makeLookupService(session: session)
        let outcome = try await lookupService.findLyrics(
            input: matchInput,
            requirement: .synchronized
        )

        if case .notFound = outcome {
            return
        }
        Issue.record("Expected a confirmed not-found outcome")
    }

    @Test func malformedLrclibTimingFallsBackForSynchronizedLookup() async throws {
        let session = makeSession()
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }
        LyricsURLProtocol.handler = { request in
            switch (request.url?.host, request.url?.path) {
                case ("lrclib.test", "/api/get"):
                    return response(
                        request: request,
                        statusCode: 200,
                        body: lrclibMalformedTimedJSON
                    )
                case ("lrclib.test", "/api/search"):
                    return response(request: request, statusCode: 200, body: "[]")
                default:
                    return response(
                        request: request,
                        statusCode: 200,
                        body: lrcmuxTimedJSON
                    )
            }
        }

        let lookupService = makeLookupService(session: session)
        let outcome = try await lookupService.findLyrics(
            input: matchInput,
            requirement: .synchronized
        )

        if case let .match(result) = outcome {
            #expect(result.provider == .lrcmux)
        } else {
            Issue.record("Expected LRCMÜX to replace unusable timing")
        }
    }

    @Test func lrclibOutageAndLrcmuxMissRemainsTemporary() async throws {
        let session = makeSession()
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }
        LyricsURLProtocol.handler = { request in
            if request.url?.host == "lrclib.test" {
                return response(request: request, statusCode: 503)
            }
            return response(request: request, statusCode: 404)
        }

        let lookupService = makeLookupService(session: session)
        do {
            _ = try await lookupService.findLyrics(
                input: matchInput,
                requirement: .synchronized
            )
            Issue.record("Expected a temporary provider failure")
        } catch let error as LyricsLookupError {
            if case let .temporarilyUnavailable(retryAfter) = error {
                #expect(retryAfter == nil)
            } else {
                Issue.record("Expected a temporary provider failure")
            }
        }
    }

    @Test func lrclibRateLimitDoesNotPreventLrcmuxFallbackOrOpenItsCooldown() async throws {
        let session = makeSession()
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }
        var lrclibRequestCount = 0
        var lrcmuxRequestCount = 0
        LyricsURLProtocol.handler = { request in
            if request.url?.host == "lrclib.test" {
                lrclibRequestCount += 1
                return response(
                    request: request,
                    statusCode: 429,
                    headers: ["Retry-After": "120"]
                )
            }
            lrcmuxRequestCount += 1
            return response(
                request: request,
                statusCode: 200,
                body: lrcmuxTimedJSON
            )
        }

        let lookupService = makeLookupService(session: session)
        _ = try await lookupService.findLyrics(
            input: matchInput,
            requirement: .synchronized
        )
        _ = try await lookupService.findLyrics(
            input: matchInput,
            requirement: .synchronized
        )

        #expect(lrclibRequestCount == 1)
        #expect(lrcmuxRequestCount == 2)
    }

    @Test func cancellationStopsBeforeTheFallbackProvider() async throws {
        let session = makeSession()
        defer {
            LyricsURLProtocol.handler = nil
            session.invalidateAndCancel()
        }
        var lrcmuxRequestCount = 0
        LyricsURLProtocol.handler = { request in
            if request.url?.host == "lrcmux.test" {
                lrcmuxRequestCount += 1
                return response(
                    request: request,
                    statusCode: 200,
                    body: lrcmuxTimedJSON
                )
            }
            return response(request: request, statusCode: 404)
        }

        let lookupService = makeLookupService(session: session)
        let lookupTask = Task {
            try await lookupService.findLyrics(
                input: matchInput,
                requirement: .synchronized
            )
        }
        try await Task.sleep(for: .milliseconds(50))
        lookupTask.cancel()

        do {
            _ = try await lookupTask.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            #expect(lrcmuxRequestCount == 0)
        }
    }

    private var matchInput: LyricsMatchInput {
        LyricsMatchInput(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 180.6
        )
    }

    private var lrclibTimedJSON: String {
        """
        {
          "id": 42,
          "trackName": "Song",
          "artistName": "Artist",
          "albumName": "Album",
          "duration": 181,
          "instrumental": false,
          "plainLyrics": "First line",
          "syncedLyrics": "[00:01.25]First line"
        }
        """
    }

    private var lrclibPlainJSON: String {
        """
        {
          "id": 43,
          "trackName": "Song",
          "artistName": "Artist",
          "albumName": "Album",
          "duration": 181,
          "instrumental": false,
          "plainLyrics": "Plain line",
          "syncedLyrics": null
        }
        """
    }

    private var lrclibMalformedTimedJSON: String {
        """
        {
          "id": 44,
          "trackName": "Song",
          "artistName": "Artist",
          "albumName": "Album",
          "duration": 181,
          "instrumental": false,
          "plainLyrics": "Plain line",
          "syncedLyrics": "Timing unavailable"
        }
        """
    }

    private var lrcmuxTimedJSON: String {
        """
        {
          "track": {
            "isrc": "TEST123",
            "title": "Song",
            "artist": "Artist",
            "album": "Album",
            "duration": 181
          },
          "meta": {
            "source": {
              "id": "ytmusic",
              "name": "YouTube Music",
              "url": "https://music.youtube.com"
            },
            "level": "line",
            "instrumental": false
          },
          "lines": [
            { "text": "First line", "start": 1250 },
            { "text": "Second line", "start": 3500 }
          ]
        }
        """
    }

    private var lrcmuxInstrumentalJSON: String {
        """
        {
          "track": {
            "isrc": "TEST123",
            "title": "Song",
            "artist": "Artist",
            "album": "Album",
            "duration": 181
          },
          "meta": {
            "source": {
              "id": "ytmusic",
              "name": "YouTube Music",
              "url": "https://music.youtube.com"
            },
            "level": "none",
            "instrumental": true
          },
          "lines": null
        }
        """
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeLookupService(session: URLSession) -> LyricsLookupService {
        LyricsLookupService(
            lrclibService: LRCLibService(
                baseURL: URL(string: "https://lrclib.test")!,
                session: session,
                clientIdentifier: "LyricsKitTests/1.0"
            ),
            lrcmuxService: LRCMuxService(
                baseURL: URL(string: "https://lrcmux.test")!,
                session: session,
                clientIdentifier: "LyricsKitTests/1.0"
            )
        )
    }

    private func response(
        request: URLRequest,
        statusCode: Int,
        headers: [String: String] = [:],
        body: String = ""
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
        return (response, Data(body.utf8))
    }
}
