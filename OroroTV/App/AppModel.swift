import Foundation
import Observation
import OroroKit

/// Something to play, with enough context to record history and resume.
struct PlaybackRequest: Identifiable, Equatable {
    let id = UUID()
    let media: MediaRef
    let title: String
    let subtitle: String?
    let showID: Int?
    let season: Int?
    let episodeNumber: String?
    /// Seconds to start from; nil plays from the beginning.
    let startAt: Double?
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case signedOut
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .signedOut
    private(set) var email: String?
    private(set) var shows: [Show] = []
    private(set) var movies: [Movie] = []
    private(set) var searchIndex = SearchIndex(shows: [], movies: [])
    /// The single source of truth for history and My List. Saved on change.
    var library: Library {
        didSet { scheduleSave() }
    }
    /// Setting this presents the player.
    var nowPlaying: PlaybackRequest?

    @ObservationIgnored private(set) var client: OroroClient?
    @ObservationIgnored private var showsByID: [Int: Show] = [:]
    @ObservationIgnored private var moviesByID: [Int: Movie] = [:]
    @ObservationIgnored private var showDetails: [Int: ShowDetail] = [:]
    @ObservationIgnored private let libraryStore = LibraryStore()
    @ObservationIgnored private let responseCache = FileResponseCache.caches()
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        library = LibraryStore().load()
        if let credentials = KeychainStore.load() {
            connect(credentials)
            phase = .loading
            Task { await loadCatalog() }
        }
    }

    // MARK: Session

    func signIn(email: String, password: String) async throws {
        let credentials = Credentials(email: email.trimmingCharacters(in: .whitespaces), password: password)
        let client = OroroClient(credentials: credentials, cache: responseCache)
        try await client.verifyCredentials()
        KeychainStore.save(credentials)
        connect(credentials, client: client)
        await loadCatalog()
    }

    func signOut() {
        KeychainStore.delete()
        responseCache.removeAll()
        client = nil
        email = nil
        shows = []
        movies = []
        showsByID = [:]
        moviesByID = [:]
        showDetails = [:]
        searchIndex = SearchIndex(shows: [], movies: [])
        phase = .signedOut
    }

    private func connect(_ credentials: Credentials, client: OroroClient? = nil) {
        self.client = client ?? OroroClient(credentials: credentials, cache: responseCache)
        email = credentials.email
    }

    // MARK: Catalog

    func loadCatalog() async {
        guard let client else { return }
        if shows.isEmpty { phase = .loading }
        do {
            async let fetchedShows = client.shows()
            async let fetchedMovies = client.movies()
            let (newShows, newMovies) = try await (fetchedShows, fetchedMovies)
            shows = newShows
            movies = newMovies
            showsByID = Dictionary(newShows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            moviesByID = Dictionary(newMovies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            searchIndex = SearchIndex(shows: newShows, movies: newMovies)
            phase = .ready
        } catch OroroError.unauthorized {
            // Password changed on the website.
            signOut()
        } catch {
            if shows.isEmpty { phase = .failed(error.localizedDescription) }
        }
    }

    func show(id: Int) -> Show? { showsByID[id] }
    func movie(id: Int) -> Movie? { moviesByID[id] }

    func title(for ref: MediaRef) -> Title? {
        switch ref {
        case .show(let id): return showsByID[id].map(Title.show)
        case .movie(let id): return moviesByID[id].map(Title.movie)
        case .episode: return nil
        }
    }

    func showDetail(id: Int) async throws -> ShowDetail {
        if let cached = showDetails[id] { return cached }
        guard let client else { throw OroroError.unauthorized }
        let detail = try await client.show(id: id)
        showDetails[id] = detail
        return detail
    }

    // MARK: Playback

    func play(_ movie: Movie, fromStart: Bool = false) {
        let media = MediaRef.movie(movie.id)
        nowPlaying = PlaybackRequest(media: media, title: movie.name, subtitle: movie.year,
                                     showID: nil, season: nil, episodeNumber: nil,
                                     startAt: fromStart ? nil : library.record(for: media)?.resumePosition)
    }

    func play(_ episode: Episode, of show: Show, fromStart: Bool = false) {
        let media = MediaRef.episode(episode.id)
        nowPlaying = PlaybackRequest(media: media, title: show.name,
                                     subtitle: "\(episode.code) · \(episode.displayName)",
                                     showID: show.id, season: episode.season,
                                     episodeNumber: episode.number,
                                     startAt: fromStart ? nil : library.record(for: media)?.resumePosition)
    }

    /// Plays whatever comes next in a show: resumes, moves on, or starts.
    /// Returns false when the user has finished the whole show.
    @discardableResult
    func continueShow(id: Int) async throws -> Bool {
        let detail = try await showDetail(id: id)
        guard let episode = library.nextEpisode(in: detail) else { return false }
        play(episode, of: detail.show)
        return true
    }

    /// Called by the player after an episode ends; queues the next one.
    func playNextEpisode(after request: PlaybackRequest) async -> Bool {
        guard case .episode(let id) = request.media, let showID = request.showID,
              let detail = try? await showDetail(id: showID),
              let next = detail.episode(after: id) else { return false }
        play(next, of: detail.show, fromStart: true)
        return true
    }

    func recordProgress(_ request: PlaybackRequest, position: Double, duration: Double) {
        library.updateProgress(for: request.media, showID: request.showID, season: request.season,
                               episodeNumber: request.episodeNumber, position: position,
                               duration: duration)
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveLibraryNow()
        }
    }

    func saveLibraryNow() {
        saveTask?.cancel()
        libraryStore.save(library)
    }
}
