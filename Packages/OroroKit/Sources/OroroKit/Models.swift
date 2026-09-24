import Foundation

// Shapes of the ororo.tv v2 API (https://front.ororo.tv/api/v2).
// Field nullability was surveyed against the full live catalog; anything seen
// as null at least once is optional here.

/// A TV show as it appears in `GET /shows`.
public struct Show: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let slug: String?
    public let year: String
    public let desc: String
    public let ended: Bool?
    /// Typical episode length in minutes.
    public let length: Int?
    public let imdbId: String?
    public let imdbRating: Double?
    public let tmdbId: String?
    public let arrayGenres: [String]
    public let arrayCountries: [String]
    public let posterThumb: String
    public let backdropUrl: String?
    /// Unix time of the most recently added episode.
    public let newestVideo: Int?
    public let updatedAt: Int?
    public let userPopularity: Int?

    public var genres: [String] { arrayGenres }
    public var posterURL: URL? { URL(string: posterThumb) }
    public var backdropURL: URL? { backdropUrl.flatMap(URL.init(string:)) }
}

/// An episode as listed inside `GET /shows/:id`. It carries no playable URL;
/// fetch `GET /episodes/:id` for that.
public struct Episode: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String?
    /// The API sends episode numbers as strings.
    public let number: String
    public let season: Int
    public let plot: String?
    public let airdate: String?
    public let resolution: String?
    public let updatedAt: Int?

    public var numberValue: Int { Int(number) ?? 0 }

    public var code: String {
        String(format: "S%02dE%02d", season, numberValue)
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return "Episode \(number)"
    }
}

/// `GET /shows/:id`: the show plus all of its episodes.
public struct ShowDetail: Decodable, Hashable, Identifiable, Sendable {
    public let show: Show
    public let seasons: Int?
    public let episodes: [Episode]

    public var id: Int { show.id }

    private enum CodingKeys: String, CodingKey { case seasons, episodes }

    public init(show: Show, seasons: Int?, episodes: [Episode]) {
        self.show = show
        self.seasons = seasons
        self.episodes = episodes
    }

    public init(from decoder: Decoder) throws {
        show = try Show(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seasons = try container.decodeIfPresent(Int.self, forKey: .seasons)
        episodes = try container.decodeIfPresent([Episode].self, forKey: .episodes) ?? []
    }

    /// Episodes in viewing order (season, then episode number).
    public var orderedEpisodes: [Episode] { episodes.sorted(by: Episode.viewingOrder) }

    public var seasonNumbers: [Int] { Array(Set(episodes.map(\.season))).sorted() }

    public func episodes(inSeason season: Int) -> [Episode] {
        orderedEpisodes.filter { $0.season == season }
    }

    /// The episode after `episodeID` in viewing order, if any.
    public func episode(after episodeID: Int) -> Episode? {
        let ordered = orderedEpisodes
        guard let index = ordered.firstIndex(where: { $0.id == episodeID }),
              index + 1 < ordered.count else { return nil }
        return ordered[index + 1]
    }
}

extension Episode {
    static func viewingOrder(_ a: Episode, _ b: Episode) -> Bool {
        if a.season != b.season { return a.season < b.season }
        if a.numberValue != b.numberValue { return a.numberValue < b.numberValue }
        return a.id < b.id
    }
}

/// A movie as it appears in `GET /movies`.
public struct Movie: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let year: String
    public let desc: String
    /// Runtime in minutes.
    public let length: Int?
    public let imdbId: String?
    public let imdbRating: Double?
    public let arrayGenres: [String]
    public let arrayCountries: [String]
    public let posterThumb: String
    public let backdropUrl: String?
    public let resolution: String?
    public let updatedAt: Int?

    public var genres: [String] { arrayGenres }
    public var posterURL: URL? { URL(string: posterThumb) }
    public var backdropURL: URL? { backdropUrl.flatMap(URL.init(string:)) }
}

public struct Subtitle: Codable, Hashable, Sendable {
    /// ISO 639-1 code, e.g. "en", "ru".
    public let lang: String
    public let url: URL

    public init(lang: String, url: URL) {
        self.lang = lang
        self.url = url
    }
}

/// Everything needed to start playback. Built from `GET /episodes/:id` or
/// `GET /movies/:id`. The URLs are signed and expire (about 32 hours), so
/// fetch a fresh one right before playing rather than caching it.
public struct PlaybackInfo: Hashable, Sendable {
    public let media: MediaRef
    /// HLS (fMP4) master playlist.
    public let streamURL: URL
    /// Progressive 1080p MP4, if offered.
    public let downloadURL: URL?
    public let subtitles: [Subtitle]

    public func subtitle(for lang: String) -> Subtitle? {
        subtitles.first { $0.lang == lang }
    }
}

/// `GET /episodes/:id`.
public struct EpisodeDetail: Decodable, Hashable, Sendable {
    public let episode: Episode
    public let showName: String?
    public let url: String?
    public let downloadUrl: String?
    public let subtitles: [Subtitle]

    private enum CodingKeys: String, CodingKey { case showName, url, downloadUrl, subtitles }

    public init(from decoder: Decoder) throws {
        episode = try Episode(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showName = try container.decodeIfPresent(String.self, forKey: .showName)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        downloadUrl = try container.decodeIfPresent(String.self, forKey: .downloadUrl)
        subtitles = try container.decodeIfPresent([Subtitle].self, forKey: .subtitles) ?? []
    }
}

/// `GET /movies/:id`.
public struct MovieDetail: Decodable, Hashable, Sendable {
    public let movie: Movie
    public let url: String?
    public let downloadUrl: String?
    public let subtitles: [Subtitle]
    /// YouTube video id of the trailer.
    public let trailer: String?

    private enum CodingKeys: String, CodingKey { case url, downloadUrl, subtitles, trailer }

    public init(from decoder: Decoder) throws {
        movie = try Movie(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        downloadUrl = try container.decodeIfPresent(String.self, forKey: .downloadUrl)
        subtitles = try container.decodeIfPresent([Subtitle].self, forKey: .subtitles) ?? []
        trailer = try container.decodeIfPresent(String.self, forKey: .trailer)
    }
}

struct ShowList: Decodable { let shows: [Show] }
struct MovieList: Decodable { let movies: [Movie] }

/// Identifies anything the user can watch or save.
public enum MediaRef: Hashable, Sendable {
    case movie(Int)
    case show(Int)
    case episode(Int)
}

extension MediaRef: Codable, CustomStringConvertible {
    /// Compact string form ("m12", "s3", "e456"), used as a storage key so
    /// history stays small enough for tvOS's limited local storage.
    public var description: String {
        switch self {
        case .movie(let id): return "m\(id)"
        case .show(let id): return "s\(id)"
        case .episode(let id): return "e\(id)"
        }
    }

    public init?(_ string: String) {
        guard let prefix = string.first, let id = Int(string.dropFirst()) else { return nil }
        switch prefix {
        case "m": self = .movie(id)
        case "s": self = .show(id)
        case "e": self = .episode(id)
        default: return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let ref = MediaRef(string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Bad MediaRef \(string)"))
        }
        self = ref
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension JSONDecoder {
    static let ororo: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
