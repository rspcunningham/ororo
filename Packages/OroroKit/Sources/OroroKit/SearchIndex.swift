import Foundation

/// A show or movie in the catalog.
public enum Title: Hashable, Identifiable, Sendable {
    case show(Show)
    case movie(Movie)

    public var id: MediaRef {
        switch self {
        case .show(let show): return .show(show.id)
        case .movie(let movie): return .movie(movie.id)
        }
    }

    public var name: String {
        switch self {
        case .show(let show): return show.name
        case .movie(let movie): return movie.name
        }
    }

    public var year: String {
        switch self {
        case .show(let show): return show.year
        case .movie(let movie): return movie.year
        }
    }

    public var posterURL: URL? {
        switch self {
        case .show(let show): return show.posterURL
        case .movie(let movie): return movie.posterURL
        }
    }

    public var genres: [String] {
        switch self {
        case .show(let show): return show.genres
        case .movie(let movie): return movie.genres
        }
    }

    public var imdbRating: Double? {
        switch self {
        case .show(let show): return show.imdbRating
        case .movie(let movie): return movie.imdbRating
        }
    }
}

/// In-memory title search over the whole catalog.
///
/// The API has no search endpoint, but the full catalog (about 12,000 titles)
/// is already downloaded for browsing, so searching it locally is instant and
/// works offline.
public struct SearchIndex: Sendable {
    private struct Entry: Sendable {
        let title: Title
        let normalized: String
        let words: [String]
    }

    private let entries: [Entry]

    public init(shows: [Show], movies: [Movie]) {
        let titles = shows.map(Title.show) + movies.map(Title.movie)
        entries = titles.map { title in
            let normalized = SearchIndex.normalize(title.name)
            return Entry(title: title, normalized: normalized, words: SearchIndex.words(normalized))
        }
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// Titles matching `query`, best first.
    ///
    /// Ranking: exact title, then title prefix, then every query word
    /// prefixing some title word, then plain substring. Ties go to the
    /// higher-rated title, then the newer one.
    public func search(_ query: String, limit: Int = 60) -> [Title] {
        let normalizedQuery = SearchIndex.normalize(query)
        let queryWords = SearchIndex.words(normalizedQuery)
        guard !queryWords.isEmpty else { return [] }

        var scored: [(score: Int, entry: Entry)] = []
        for entry in entries {
            let score: Int
            if entry.normalized == normalizedQuery {
                score = 400
            } else if entry.normalized.hasPrefix(normalizedQuery) {
                score = 300
            } else if queryWords.allSatisfy({ word in entry.words.contains { $0.hasPrefix(word) } }) {
                // Titles whose first word matches rank above the rest.
                score = entry.words.first?.hasPrefix(queryWords[0]) == true ? 250 : 200
            } else if normalizedQuery.count >= 3, entry.normalized.contains(normalizedQuery) {
                score = 100
            } else {
                continue
            }
            scored.append((score, entry))
        }

        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            let ra = a.entry.title.imdbRating ?? 0, rb = b.entry.title.imdbRating ?? 0
            if ra != rb { return ra > rb }
            return a.entry.title.year > b.entry.title.year
        }
        return scored.prefix(limit).map(\.entry.title)
    }

    /// Lowercases, strips accents and turns punctuation into spaces, so
    /// "Amélie" matches "amelie" and "Grey's" matches "greys".
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    static func words(_ normalized: String) -> [String] {
        normalized.split(separator: " ").map(String.init)
    }
}
