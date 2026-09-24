import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Credentials: Hashable, Sendable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }

    var authorizationHeader: String {
        "Basic " + Data("\(email):\(password)".utf8).base64EncodedString()
    }
}

public enum OroroError: Error, Equatable, Sendable {
    /// 401: wrong email or password.
    case unauthorized
    /// 402: the free account's daily limit is used up.
    case limitReached
    /// 404: no such show, movie or episode.
    case notFound
    /// The item exists but the API returned no playable URL.
    case notPlayable
    case http(status: Int)
    /// Every API host failed at the network level.
    case network(String)
    case decoding(String)
}

extension OroroError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Wrong email or password."
        case .limitReached: return "You've reached the free daily limit. A subscription removes it."
        case .notFound: return "This title is no longer available."
        case .notPlayable: return "This title can't be played right now."
        case .http(let status): return "Ororo returned an error (HTTP \(status))."
        case .network(let message): return "Couldn't reach Ororo: \(message)"
        case .decoding(let message): return "Unexpected response from Ororo: \(message)"
        }
    }
}

/// Sends one HTTP request. Abstracted so tests can stub the network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), http))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }.resume()
        }
    }
}

/// Client for the ororo.tv v2 API.
///
/// - Authenticates every request with HTTP Basic auth.
/// - Falls back to the mirror host when the main one is unreachable, and
///   remembers whichever host last worked.
/// - Revalidates the large catalog lists with ETags, so an unchanged catalog
///   costs a 304 instead of several megabytes.
public actor OroroClient {
    public static let defaultHosts = ["front.ororo.tv", "front.ororo-mirror.tv"]

    private let credentials: Credentials
    private let transport: HTTPTransport
    private let cache: ResponseCache?
    private let hosts: [String]
    private var activeHost: String?
    private let timeout: TimeInterval

    public init(credentials: Credentials,
                transport: HTTPTransport = URLSessionTransport(),
                cache: ResponseCache? = nil,
                hosts: [String] = OroroClient.defaultHosts,
                timeout: TimeInterval = 30) {
        self.credentials = credentials
        self.transport = transport
        self.cache = cache
        self.hosts = hosts
        self.timeout = timeout
    }

    // MARK: Catalog

    public func shows() async throws -> [Show] {
        try decode(ShowList.self, from: await get("/shows", revalidate: true)).shows
    }

    public func movies() async throws -> [Movie] {
        try decode(MovieList.self, from: await get("/movies", revalidate: true)).movies
    }

    public func show(id: Int) async throws -> ShowDetail {
        try decode(ShowDetail.self, from: await get("/shows/\(id)"))
    }

    // MARK: Playback

    public func episode(id: Int) async throws -> EpisodeDetail {
        try decode(EpisodeDetail.self, from: await get("/episodes/\(id)"))
    }

    public func movie(id: Int) async throws -> MovieDetail {
        try decode(MovieDetail.self, from: await get("/movies/\(id)"))
    }

    /// Fetches a freshly signed stream URL for a movie or episode.
    public func playback(for media: MediaRef) async throws -> PlaybackInfo {
        let url: String?, download: String?, subtitles: [Subtitle]
        switch media {
        case .episode(let id):
            let detail = try await episode(id: id)
            (url, download, subtitles) = (detail.url, detail.downloadUrl, detail.subtitles)
        case .movie(let id):
            let detail = try await movie(id: id)
            (url, download, subtitles) = (detail.url, detail.downloadUrl, detail.subtitles)
        case .show:
            throw OroroError.notPlayable
        }
        guard let url, let streamURL = URL(string: url) else { throw OroroError.notPlayable }
        return PlaybackInfo(media: media,
                            streamURL: streamURL,
                            downloadURL: download.flatMap(URL.init(string:)),
                            subtitles: subtitles)
    }

    /// Checks the credentials without downloading the whole catalog.
    /// `/shows/:id` for a missing id answers 401 for bad credentials and
    /// 404 for good ones, which makes it a cheap login probe.
    public func verifyCredentials() async throws {
        do {
            _ = try await get("/shows/0")
        } catch OroroError.notFound {
            return
        }
    }

    // MARK: Transport

    private func get(_ path: String, revalidate: Bool = false) async throws -> Data {
        let cached = revalidate ? cache?.entry(for: path) : nil
        var lastNetworkError: Error?

        for host in orderedHosts() {
            var request = URLRequest(url: URL(string: "https://\(host)/api/v2\(path)")!)
            request.timeoutInterval = timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
            if let etag = cached?.etag {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }

            let data: Data, response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch {
                // Network-level failure: try the next host.
                if activeHost == host { activeHost = nil }
                lastNetworkError = error
                continue
            }

            // The host answered, even if with an error status, so it works.
            activeHost = host

            switch response.statusCode {
            case 200..<300:
                if revalidate, let etag = response.value(forHTTPHeaderField: "ETag") {
                    cache?.store(CachedResponse(etag: etag, data: data), for: path)
                }
                return data
            case 304:
                if let cached { return cached.data }
                throw OroroError.http(status: 304)
            case 401: throw OroroError.unauthorized
            case 402: throw OroroError.limitReached
            case 404: throw OroroError.notFound
            default: throw OroroError.http(status: response.statusCode)
            }
        }

        throw OroroError.network(lastNetworkError?.localizedDescription ?? "no hosts configured")
    }

    private func orderedHosts() -> [String] {
        guard let activeHost else { return hosts }
        return [activeHost] + hosts.filter { $0 != activeHost }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.ororo.decode(type, from: data)
        } catch {
            throw OroroError.decoding(String(describing: error))
        }
    }
}
