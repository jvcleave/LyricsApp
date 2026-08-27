import Foundation

public enum LRCLibServiceError: LocalizedError, Sendable {
    case invalidRequest
    case rateLimited(retryAfter: TimeInterval?)
    case server(statusCode: Int, message: String?)
    case network(String)
    case decoding

    public var errorDescription: String? {
        switch self {
            case .invalidRequest:
                return "The lyrics request could not be created."
            case let .rateLimited(retryAfter):
                if let retryAfter {
                    return "LRCLIB is receiving too many requests. Please try again in \(Int(ceil(retryAfter))) seconds."
                }
                return "LRCLIB is receiving too many requests. Please wait before trying again."
            case let .server(statusCode, message):
                if let message, message.isEmpty == false {
                    return "LRCLIB returned an error (\(statusCode)): \(message)"
                }
                return "LRCLIB returned an error (\(statusCode))."
            case let .network(message):
                return "The lyrics service could not be reached: \(message)"
            case .decoding:
                return "LRCLIB returned a response this version of LyricsKit could not read."
        }
    }
}

public struct LRCLibService: Sendable {
    private struct APIErrorResponse: Decodable {
        let message: String?
    }

    private static let baseURL = URL(string: "https://lrclib.net")!

    private let session: URLSession
    private let clientIdentifier: String

    public init(
        session: URLSession = .shared,
        clientIdentifier: String = "LyricsKit/1.0 (https://github.com/jvcleave/LyricsApp)"
    ) {
        self.session = session
        self.clientIdentifier = clientIdentifier
    }

    public func exactMatch(input: LyricsMatchInput) async throws -> LyricsResult? {
        if input.title.isEmpty || input.artist.isEmpty {
            return nil
        }

        var queryItems = [
            URLQueryItem(name: "track_name", value: input.title),
            URLQueryItem(name: "artist_name", value: input.artist),
        ]
        if input.album.isEmpty == false {
            queryItems.append(URLQueryItem(name: "album_name", value: input.album))
        }
        if let duration = input.duration, duration.isFinite, duration > 0 {
            queryItems.append(
                URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
            )
        }

        let response = try await response(
            path: ["api", "get"],
            queryItems: queryItems
        )
        if response.http.statusCode == 404 {
            return nil
        }
        try validate(response)
        do {
            return try JSONDecoder().decode(LyricsResult.self, from: response.data)
        } catch {
            throw LRCLibServiceError.decoding
        }
    }

    public func search(input: LyricsMatchInput) async throws -> [LyricsResult] {
        let queryItems: [URLQueryItem]
        if input.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems = [URLQueryItem(name: "q", value: input.title)]
        } else {
            queryItems = [
                URLQueryItem(name: "track_name", value: input.title),
                URLQueryItem(name: "artist_name", value: input.artist),
            ]
        }

        let response = try await response(
            path: ["api", "search"],
            queryItems: queryItems
        )
        try validate(response)
        do {
            return try JSONDecoder().decode([LyricsResult].self, from: response.data)
        } catch {
            throw LRCLibServiceError.decoding
        }
    }

    private func response(
        path: [String],
        queryItems: [URLQueryItem]
    ) async throws -> (data: Data, http: HTTPURLResponse) {
        let endpoint = path.reduce(Self.baseURL) { url, component in
            url.appendingPathComponent(component)
        }
        if var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) {
            components.queryItems = queryItems
            if let url = components.url {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 30
                request.setValue(clientIdentifier, forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                do {
                    let (data, response) = try await session.data(for: request)
                    if let http = response as? HTTPURLResponse {
                        return (data, http)
                    }
                    throw LRCLibServiceError.server(statusCode: 0, message: nil)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as LRCLibServiceError {
                    throw error
                } catch let error as URLError where error.code == .cancelled {
                    throw CancellationError()
                } catch {
                    throw LRCLibServiceError.network(error.localizedDescription)
                }
            }
        }
        throw LRCLibServiceError.invalidRequest
    }

    private func validate(_ response: (data: Data, http: HTTPURLResponse)) throws {
        switch response.http.statusCode {
            case 200 ..< 300:
                return
            case 429:
                let retryAfter = response.http
                    .value(forHTTPHeaderField: "Retry-After")
                    .flatMap(TimeInterval.init)
                throw LRCLibServiceError.rateLimited(retryAfter: retryAfter)
            default:
                let message = try? JSONDecoder()
                    .decode(APIErrorResponse.self, from: response.data)
                    .message
                throw LRCLibServiceError.server(
                    statusCode: response.http.statusCode,
                    message: message
                )
        }
    }
}
