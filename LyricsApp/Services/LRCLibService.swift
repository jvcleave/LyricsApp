import Foundation

enum LRCLibServiceError: LocalizedError, Sendable {
    case invalidRequest
    case rateLimited(retryAfter: TimeInterval?)
    case server(statusCode: Int, message: String?)
    case network(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "The lyrics request could not be created."
        case let .rateLimited(retryAfter):
            if let retryAfter {
                "LRCLIB is receiving too many requests. Please try again in \(Int(ceil(retryAfter))) seconds."
            } else {
                "LRCLIB is receiving too many requests. Please wait before trying again."
            }
        case let .server(statusCode, message):
            if let message, !message.isEmpty {
                "LRCLIB returned an error (\(statusCode)): \(message)"
            } else {
                "LRCLIB returned an error (\(statusCode))."
            }
        case let .network(message):
            "The lyrics service could not be reached: \(message)"
        case .decoding:
            "LRCLIB returned a response this version of LyricsApp could not read."
        }
    }
}

struct LRCLibService: Sendable {
    private struct APIErrorResponse: Decodable {
        let message: String?
    }

    private static let baseURL = URL(string: "https://lrclib.net")!
    private static let clientIdentifier = "LyricsApp v0.1"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func exactMatch(for input: LyricsMatchInput) async throws -> LyricsResult? {
        guard !input.title.isEmpty, !input.artist.isEmpty else { return nil }

        var items = [
            URLQueryItem(name: "track_name", value: input.title),
            URLQueryItem(name: "artist_name", value: input.artist),
        ]
        if !input.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: input.album))
        }
        if let duration = input.duration, duration.isFinite, duration > 0 {
            items.append(
                URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
            )
        }

        let response = try await response(path: ["api", "get"], queryItems: items)
        if response.http.statusCode == 404 {
            return nil
        }
        try validate(response)
        return try decode(LyricsResult.self, from: response.data)
    }

    func search(for input: LyricsMatchInput) async throws -> [LyricsResult] {
        let items: [URLQueryItem]
        if input.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items = [URLQueryItem(name: "q", value: input.title)]
        } else {
            items = [
                URLQueryItem(name: "track_name", value: input.title),
                URLQueryItem(name: "artist_name", value: input.artist),
            ]
        }

        let response = try await response(path: ["api", "search"], queryItems: items)
        try validate(response)
        return try decode([LyricsResult].self, from: response.data)
    }

    private func response(
        path: [String],
        queryItems: [URLQueryItem]
    ) async throws -> (data: Data, http: HTTPURLResponse) {
        let endpoint = path.reduce(Self.baseURL) { url, component in
            url.appendingPathComponent(component)
        }
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw LRCLibServiceError.invalidRequest
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw LRCLibServiceError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(Self.clientIdentifier, forHTTPHeaderField: "Lrclib-Client")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LRCLibServiceError.server(statusCode: 0, message: nil)
            }
            return (data, http)
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

    private func validate(_ response: (data: Data, http: HTTPURLResponse)) throws {
        switch response.http.statusCode {
        case 200..<300:
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

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LRCLibServiceError.decoding
        }
    }
}
