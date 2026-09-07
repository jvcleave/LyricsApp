import Foundation

public enum LRCMuxServiceError: LocalizedError, Sendable {
    case invalidRequest
    case rateLimited(retryAfter: TimeInterval?)
    case server(statusCode: Int, message: String?)
    case network(String)
    case decoding

    public var errorDescription: String? {
        switch self {
            case .invalidRequest:
                return "The LRCMÜX request could not be created."
            case let .rateLimited(retryAfter):
                if let retryAfter {
                    return "LRCMÜX is receiving too many requests. Please try again in \(Int(ceil(retryAfter))) seconds."
                }
                return "LRCMÜX is receiving too many requests. Please wait before trying again."
            case let .server(statusCode, message):
                if let message, message.isEmpty == false {
                    return "LRCMÜX returned an error (\(statusCode)): \(message)"
                }
                return "LRCMÜX returned an error (\(statusCode))."
            case let .network(message):
                return "LRCMÜX could not be reached: \(message)"
            case .decoding:
                return "LRCMÜX returned a response this version of LyricsKit could not read."
        }
    }
}

public struct LRCMuxService: Sendable {
    private struct APIErrorResponse: Decodable {
        let detail: String?
    }

    private struct APIResponse: Decodable {
        struct Track: Decodable {
            let isrc: String
            let title: String
            let artist: String
            let album: String
            let duration: Int
        }

        struct Metadata: Decodable {
            let source: Source?
            let level: String
            let instrumental: Bool?
        }

        struct Source: Decodable {
            let id: String
            let name: String
            let url: URL?
        }

        struct Line: Decodable {
            let text: String
            let start: Int?
        }

        let track: Track
        let meta: Metadata
        let lines: [Line]?
    }

    private let baseURL: URL
    private let session: URLSession
    private let clientIdentifier: String

    public init(
        session: URLSession = .shared,
        clientIdentifier: String = "LyricsKit/1.0 (https://github.com/jvcleave/LyricsApp)"
    ) {
        baseURL = URL(string: "https://api.lrcmux.dev")!
        self.session = session
        self.clientIdentifier = clientIdentifier
    }

    init(
        baseURL: URL,
        session: URLSession,
        clientIdentifier: String
    ) {
        self.baseURL = baseURL
        self.session = session
        self.clientIdentifier = clientIdentifier
    }

    public func lyrics(
        input: LyricsMatchInput,
        requirement: LyricsContentRequirement
    ) async throws -> LyricsResult? {
        if input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || input.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LRCMuxServiceError.invalidRequest
        }

        var queryItems = [
            URLQueryItem(name: "artist", value: input.artist),
            URLQueryItem(name: "title", value: input.title),
        ]
        if input.album.isEmpty == false {
            queryItems.append(URLQueryItem(name: "album", value: input.album))
        }
        if let duration = input.duration, duration.isFinite, duration > 0 {
            queryItems.append(
                URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
            )
        }
        queryItems.append(URLQueryItem(name: "level", value: "line"))
        queryItems.append(URLQueryItem(name: "strict", value: requirement == .synchronized ? "true" : "false"))
        queryItems.append(URLQueryItem(name: "format", value: "json"))
        queryItems.append(URLQueryItem(name: "sources", value: "!lrclib"))

        let endpoint = baseURL.appendingPathComponent("get")
        if var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) {
            components.queryItems = queryItems
            if let url = components.url {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 30
                request.setValue(clientIdentifier, forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                let response: (data: Data, http: HTTPURLResponse)
                do {
                    let (data, urlResponse) = try await session.data(for: request)
                    if let httpResponse = urlResponse as? HTTPURLResponse {
                        response = (data, httpResponse)
                    } else {
                        throw LRCMuxServiceError.server(statusCode: 0, message: nil)
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as LRCMuxServiceError {
                    throw error
                } catch let error as URLError where error.code == .cancelled {
                    throw CancellationError()
                } catch {
                    throw LRCMuxServiceError.network(error.localizedDescription)
                }

                switch response.http.statusCode {
                    case 200 ..< 300:
                        break
                    case 404:
                        return nil
                    case 429:
                        let retryAfter = response.http
                            .value(forHTTPHeaderField: "Retry-After")
                            .flatMap(TimeInterval.init)
                        throw LRCMuxServiceError.rateLimited(retryAfter: retryAfter)
                    default:
                        let message = try? JSONDecoder()
                            .decode(APIErrorResponse.self, from: response.data)
                            .detail
                        throw LRCMuxServiceError.server(
                            statusCode: response.http.statusCode,
                            message: message
                        )
                }

                let apiResponse: APIResponse
                do {
                    apiResponse = try JSONDecoder().decode(APIResponse.self, from: response.data)
                } catch {
                    throw LRCMuxServiceError.decoding
                }

                let lyricsLines = apiResponse.lines ?? []
                let synchronizedLyrics: String?
                if apiResponse.meta.level == "line" || apiResponse.meta.level == "word" {
                    let timedLines = lyricsLines.compactMap { line -> String? in
                        if let start = line.start {
                            let minutes = start / 60_000
                            let seconds = (start % 60_000) / 1000
                            let milliseconds = start % 1000
                            return String(
                                format: "[%02d:%02d.%03d]%@",
                                locale: Locale(identifier: "en_US_POSIX"),
                                minutes,
                                seconds,
                                milliseconds,
                                line.text
                            )
                        }
                        return nil
                    }
                    synchronizedLyrics = timedLines.isEmpty ? nil : timedLines.joined(separator: "\n")
                } else {
                    synchronizedLyrics = nil
                }

                let plainLines = lyricsLines.map(\.text)
                let plainLyrics = plainLines.isEmpty ? nil : plainLines.joined(separator: "\n")
                let source = apiResponse.meta.source.map {
                    LyricsSource(id: $0.id, name: $0.name, url: $0.url)
                }
                let sourceID = source?.id ?? "unknown"
                let trackIdentity: String
                if apiResponse.track.isrc.isEmpty == false {
                    trackIdentity = apiResponse.track.isrc
                } else {
                    trackIdentity = [
                        apiResponse.track.artist,
                        apiResponse.track.title,
                        String(apiResponse.track.duration),
                    ].joined(separator: ":")
                }

                return LyricsResult(
                    id: "lrcmux:\(sourceID):\(trackIdentity)",
                    provider: .lrcmux,
                    upstreamSource: source,
                    trackName: apiResponse.track.title,
                    artistName: apiResponse.track.artist,
                    albumName: apiResponse.track.album,
                    duration: Double(apiResponse.track.duration),
                    instrumental: apiResponse.meta.instrumental ?? false,
                    plainLyrics: plainLyrics,
                    syncedLyrics: synchronizedLyrics
                )
            }
        }
        throw LRCMuxServiceError.invalidRequest
    }
}
