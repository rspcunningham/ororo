import Foundation

/// How far into a movie or episode the user got.
///
/// Records hold only IDs and numbers: tvOS gives an app about 500 KB of
/// storage that the system won't purge, so titles and artwork are looked up
/// from the catalog instead of being stored here.
public struct WatchRecord: Codable, Hashable, Sendable {
    public let media: MediaRef
    /// Set for episodes.
    public var showID: Int?
    public var season: Int?
    public var episodeNumber: String?
    /// Seconds.
    public var position: Double
    /// Seconds; 0 until the player knows the duration.
    public var duration: Double
    /// Unix time of the last update.
    public var updatedAt: Int

    /// Treat as watched once the credits are likely rolling.
    public var isFinished: Bool {
        guard duration > 0 else { return false }
        return position / duration >= 0.92 || duration - position < 60
    }

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// Where the player should start: nil means from the beginning.
    public var resumePosition: Double? {
        guard !isFinished, position >= 15 else { return nil }
        // Back up a few seconds so the user regains context.
        return max(position - 5, 0)
    }

    /// Movies are their own group; episodes group under their show.
    public var groupKey: MediaRef {
        if let showID { return .show(showID) }
        return media
    }

    private enum CodingKeys: String, CodingKey {
        case media = "m", showID = "s", season = "se", episodeNumber = "n"
        case position = "p", duration = "d", updatedAt = "t"
    }
}

/// The user's watch history and "My List". A value type; the app owns the
/// single instance and persists it with `LibraryStore`.
public struct Library: Codable, Equatable, Sendable {
    public static let maxRecords = 2000

    private(set) var records: [MediaRef: WatchRecord] = [:]
    /// Saved shows and movies, with the Unix time they were added.
    private(set) var saved: [MediaRef: Int] = [:]

    public init() {}

    // MARK: History

    public func record(for media: MediaRef) -> WatchRecord? {
        records[media]
    }

    public var allRecords: [WatchRecord] {
        records.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    public mutating func updateProgress(for media: MediaRef,
                                        showID: Int? = nil,
                                        season: Int? = nil,
                                        episodeNumber: String? = nil,
                                        position: Double,
                                        duration: Double,
                                        at date: Date = Date()) {
        guard position.isFinite, duration.isFinite else { return }
        var record = records[media] ?? WatchRecord(media: media, showID: showID, season: season,
                                                   episodeNumber: episodeNumber, position: 0,
                                                   duration: 0, updatedAt: 0)
        record.showID = showID ?? record.showID
        record.season = season ?? record.season
        record.episodeNumber = episodeNumber ?? record.episodeNumber
        record.position = max(position, 0)
        if duration > 0 { record.duration = duration }
        record.updatedAt = Int(date.timeIntervalSince1970)
        records[media] = record
        prune()
    }

    public mutating func markWatched(_ media: MediaRef, showID: Int? = nil, season: Int? = nil,
                                     episodeNumber: String? = nil, at date: Date = Date()) {
        let duration = max(records[media]?.duration ?? 0, 1)
        updateProgress(for: media, showID: showID, season: season, episodeNumber: episodeNumber,
                       position: duration, duration: duration, at: date)
    }

    public mutating func markUnwatched(_ media: MediaRef) {
        records[media] = nil
    }

    /// Removes a movie or a whole show from history (and so from
    /// Continue Watching).
    public mutating func removeFromHistory(_ group: MediaRef) {
        records = records.filter { $0.value.groupKey != group }
    }

    public mutating func clearHistory() {
        records = [:]
    }

    /// The most recently watched episode of a show.
    public func lastWatchedEpisode(ofShow showID: Int) -> WatchRecord? {
        records.values
            .filter { $0.showID == showID }
            .max { $0.updatedAt < $1.updatedAt }
    }

    /// One entry per movie or show, most recent first.
    ///
    /// Finished movies are left out. A show's entry is its latest episode
    /// even when finished: the caller should then offer the next episode,
    /// and drop the show if there is none.
    public func continueWatching(limit: Int = 20) -> [WatchRecord] {
        var latest: [MediaRef: WatchRecord] = [:]
        for record in records.values {
            if let current = latest[record.groupKey], current.updatedAt >= record.updatedAt { continue }
            latest[record.groupKey] = record
        }
        return latest.values
            .filter { !($0.showID == nil && $0.isFinished) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    /// Which episode "Play" should start for a show: an unfinished one
    /// resumes, a finished one moves on to the next, and a never-watched
    /// show starts at its first episode.
    public func nextEpisode(in show: ShowDetail) -> Episode? {
        let ordered = show.orderedEpisodes
        guard let last = lastWatchedEpisode(ofShow: show.id),
              case .episode(let lastID) = last.media,
              let lastEpisode = ordered.first(where: { $0.id == lastID }) else {
            return ordered.first
        }
        return last.isFinished ? show.episode(after: lastEpisode.id) : lastEpisode
    }

    // MARK: My List

    public func isSaved(_ media: MediaRef) -> Bool {
        saved[media] != nil
    }

    public var savedItems: [MediaRef] {
        saved.sorted { $0.value > $1.value }.map(\.key)
    }

    public mutating func toggleSaved(_ media: MediaRef, at date: Date = Date()) {
        if saved[media] == nil {
            saved[media] = Int(date.timeIntervalSince1970)
        } else {
            saved[media] = nil
        }
    }

    // MARK: Storage

    private mutating func prune() {
        guard records.count > Library.maxRecords else { return }
        let keep = records.values.sorted { $0.updatedAt > $1.updatedAt }.prefix(Library.maxRecords)
        records = Dictionary(uniqueKeysWithValues: keep.map { ($0.media, $0) })
    }

    private enum CodingKeys: String, CodingKey { case records = "r", saved = "l" }

    private struct SavedEntry: Codable {
        let m: MediaRef
        let t: Int
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let list = try container.decodeIfPresent([WatchRecord].self, forKey: .records) ?? []
        records = Dictionary(list.map { ($0.media, $0) }, uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 })
        let savedList = try container.decodeIfPresent([SavedEntry].self, forKey: .saved) ?? []
        saved = Dictionary(savedList.map { ($0.m, $0.t) }, uniquingKeysWith: max)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(allRecords, forKey: .records)
        try container.encode(saved.map { SavedEntry(m: $0.key, t: $0.value) }.sorted { $0.t > $1.t },
                             forKey: .saved)
    }
}

/// Anything that stores data by key. `UserDefaults` conforms, and so does
/// `NSUbiquitousKeyValueStore` for iCloud sync between devices.
public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: KeyValueStore {}

/// Loads and saves the `Library` as one compact JSON value.
public struct LibraryStore {
    public let store: KeyValueStore
    public let key: String

    public init(store: KeyValueStore = UserDefaults.standard, key: String = "ororo.library.v1") {
        self.store = store
        self.key = key
    }

    public func load() -> Library {
        guard let data = store.data(forKey: key),
              let library = try? JSONDecoder().decode(Library.self, from: data) else { return Library() }
        return library
    }

    @discardableResult
    public func save(_ library: Library) -> Int {
        guard let data = try? JSONEncoder().encode(library) else { return 0 }
        store.set(data, forKey: key)
        return data.count
    }
}
