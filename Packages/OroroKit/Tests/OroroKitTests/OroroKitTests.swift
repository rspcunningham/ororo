import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OroroKit

func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

final class ModelTests: XCTestCase {
    func testDecodesShowsWithNulls() throws {
        let shows = try JSONDecoder.ororo.decode(ShowList.self, from: fixture("shows.json")).shows
        XCTAssertEqual(shows.count, 2)
        XCTAssertEqual(shows[0].name, "Death in Paradise")
        XCTAssertEqual(shows[0].genres, ["Comedy", "Crime", "Drama", "Mystery"])
        XCTAssertEqual(shows[0].imdbRating, 7.8)
        XCTAssertNil(shows[1].imdbRating)
        XCTAssertNil(shows[1].length)
        XCTAssertNil(shows[1].backdropURL)
    }

    func testShowDetailOrdersEpisodesNumerically() throws {
        let detail = try JSONDecoder.ororo.decode(ShowDetail.self, from: fixture("show_detail.json"))
        XCTAssertEqual(detail.show.name, "Death in Paradise")
        XCTAssertEqual(detail.orderedEpisodes.map(\.id), [101, 102, 110, 201])
        XCTAssertEqual(detail.seasonNumbers, [1, 2])
        XCTAssertEqual(detail.episode(after: 110)?.id, 201)
        XCTAssertNil(detail.episode(after: 201))
        XCTAssertEqual(detail.episodes.first { $0.id == 201 }?.displayName, "Episode 1")
        XCTAssertEqual(detail.episodes.first { $0.id == 110 }?.code, "S01E10")
    }

    func testDecodesEpisodeAndMovieDetail() throws {
        let episode = try JSONDecoder.ororo.decode(EpisodeDetail.self, from: fixture("episode_detail.json"))
        XCTAssertEqual(episode.episode.season, 14)
        XCTAssertEqual(episode.showName, "Death in Paradise")
        XCTAssertEqual(episode.subtitles.map(\.lang), ["en", "ru"])
        XCTAssertTrue(episode.url?.contains("playlist_fmp4.m3u8") == true)

        let movie = try JSONDecoder.ororo.decode(MovieDetail.self, from: fixture("movie_detail.json"))
        XCTAssertEqual(movie.movie.name, "Vesper")
        XCTAssertEqual(movie.trailer, "P9hjdBePjHE")
    }

    func testMediaRefRoundTrip() throws {
        for ref in [MediaRef.movie(7), .show(8), .episode(9)] {
            XCTAssertEqual(MediaRef(ref.description), ref)
        }
        XCTAssertNil(MediaRef("x1"))
        XCTAssertNil(MediaRef("m"))
    }
}

final class SearchTests: XCTestCase {
    var index: SearchIndex!

    override func setUpWithError() throws {
        let shows = try JSONDecoder.ororo.decode(ShowList.self, from: fixture("shows.json")).shows
        let movies = try JSONDecoder.ororo.decode(MovieList.self, from: fixture("movies.json")).movies
        index = SearchIndex(shows: shows, movies: movies)
    }

    func testIgnoresCaseAccentsAndApostrophes() {
        XCTAssertEqual(index.search("amelie").map(\.name), ["Amélie"])
        XCTAssertEqual(index.search("greys").map(\.name), ["Grey's Anatomy"])
        XCTAssertEqual(index.search("GREY'S ANAT").map(\.name), ["Grey's Anatomy"])
    }

    func testMatchesWordPrefixesInAnyOrder() {
        XCTAssertEqual(index.search("para death").map(\.name), ["Death in Paradise"])
        XCTAssertEqual(index.search("par").map(\.name), ["Death in Paradise"])
    }

    func testEmptyAndMissingQueries() {
        XCTAssertTrue(index.search("   ").isEmpty)
        XCTAssertTrue(index.search("zzzz").isEmpty)
    }

    func testExactMatchRanksFirst() {
        let shows = [makeShow(1, "Paradise Lost", rating: 9), makeShow(2, "Paradise", rating: 5)]
        let results = SearchIndex(shows: shows, movies: []).search("paradise")
        XCTAssertEqual(results.map(\.name), ["Paradise", "Paradise Lost"])
    }

    private func makeShow(_ id: Int, _ name: String, rating: Double) -> Show {
        Show(id: id, name: name, slug: nil, year: "2000", desc: "", ended: nil, length: nil,
             imdbId: nil, imdbRating: rating, tmdbId: nil, arrayGenres: [], arrayCountries: [],
             posterThumb: "", backdropUrl: nil, newestVideo: nil, updatedAt: nil, userPopularity: nil)
    }
}

final class WebVTTTests: XCTestCase {
    func testParsesCuesAndStripsMarkup() throws {
        let track = SubtitleTrack(webVTT: String(decoding: try fixture("sample.vtt"), as: UTF8.self))
        XCTAssertEqual(track.cues.count, 4)
        XCTAssertEqual(track.text(at: 24), "Janelle! Good to see you again.")
        XCTAssertEqual(track.text(at: 27.5), "And you.")
        XCTAssertNil(track.text(at: 10))
        XCTAssertNil(track.text(at: 29))
        // Short "mm:ss.ttt" timestamps, SSA tags and entities.
        XCTAssertEqual(track.text(at: 31.7), "JANELLE CHUCKLES\nWhere's Patrick? & co.")
        // Overlapping cues are shown together.
        XCTAssertEqual(track.text(at: 33), "JANELLE CHUCKLES\nWhere's Patrick? & co.\nOverlapping cue.")
    }

    func testCRLFAndCommaDecimals() {
        let track = SubtitleTrack(webVTT: "\u{FEFF}WEBVTT\r\n\r\n00:00:01,000 --> 00:00:02,500\r\nHi\r\n")
        XCTAssertEqual(track.text(at: 1.2), "Hi")
    }
}

final class LibraryTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)

    func testResumeAndFinish() {
        var library = Library()
        library.updateProgress(for: .movie(1), position: 600, duration: 6000, at: start)
        XCTAssertEqual(library.record(for: .movie(1))?.resumePosition, 595)

        library.updateProgress(for: .movie(1), position: 5980, duration: 6000, at: start)
        XCTAssertTrue(library.record(for: .movie(1))!.isFinished)
        XCTAssertNil(library.record(for: .movie(1))?.resumePosition)
        XCTAssertTrue(library.continueWatching().isEmpty, "finished movies leave Continue Watching")
    }

    func testContinueWatchingGroupsEpisodesByShow() {
        var library = Library()
        library.updateProgress(for: .episode(101), showID: 3934, season: 1, episodeNumber: "1",
                               position: 3000, duration: 3000, at: start)
        library.updateProgress(for: .episode(102), showID: 3934, season: 1, episodeNumber: "2",
                               position: 100, duration: 3000, at: start.addingTimeInterval(60))
        library.updateProgress(for: .movie(5), position: 100, duration: 3000, at: start.addingTimeInterval(30))

        let row = library.continueWatching()
        XCTAssertEqual(row.map(\.media), [.episode(102), .movie(5)])
    }

    func testNextEpisode() throws {
        let show = try JSONDecoder.ororo.decode(ShowDetail.self, from: fixture("show_detail.json"))
        var library = Library()
        XCTAssertEqual(library.nextEpisode(in: show)?.id, 101, "never watched: start at the beginning")

        library.updateProgress(for: .episode(102), showID: 3934, position: 200, duration: 3000, at: start)
        XCTAssertEqual(library.nextEpisode(in: show)?.id, 102, "unfinished: resume it")

        library.markWatched(.episode(102), showID: 3934, at: start.addingTimeInterval(10))
        XCTAssertEqual(library.nextEpisode(in: show)?.id, 110, "finished: go to the next one")

        library.markWatched(.episode(201), showID: 3934, at: start.addingTimeInterval(20))
        XCTAssertNil(library.nextEpisode(in: show), "finished the last episode")
    }

    func testRemoveShowFromHistory() {
        var library = Library()
        library.updateProgress(for: .episode(1), showID: 9, position: 50, duration: 100, at: start)
        library.updateProgress(for: .episode(2), showID: 9, position: 50, duration: 100, at: start)
        library.updateProgress(for: .movie(3), position: 50, duration: 100, at: start)
        library.removeFromHistory(.show(9))
        XCTAssertEqual(library.allRecords.map(\.media), [.movie(3)])
    }

    func testMyList() {
        var library = Library()
        library.toggleSaved(.show(1), at: start)
        library.toggleSaved(.movie(2), at: start.addingTimeInterval(5))
        XCTAssertEqual(library.savedItems, [.movie(2), .show(1)])
        library.toggleSaved(.show(1))
        XCTAssertFalse(library.isSaved(.show(1)))
    }

    func testPersistsCompactlyWithinTVOSLimits() {
        let defaults = UserDefaults(suiteName: "ororo-tests-\(UUID().uuidString)")!
        let store = LibraryStore(store: defaults)
        var library = Library()
        for id in 0..<(Library.maxRecords + 100) {
            library.updateProgress(for: .episode(100_000 + id), showID: 4000, season: 12,
                                   episodeNumber: "\(id % 30)", position: 1234.5, duration: 3600,
                                   at: start.addingTimeInterval(Double(id)))
        }
        for id in 0..<200 { library.toggleSaved(.movie(id)) }
        XCTAssertEqual(library.allRecords.count, Library.maxRecords, "oldest records are pruned")

        let bytes = store.save(library)
        XCTAssertLessThan(bytes, 250_000, "must leave room in tvOS's ~500 KB of UserDefaults")
        XCTAssertEqual(store.load(), library)
    }
}

// MARK: - Client

private final class StubTransport: HTTPTransport, @unchecked Sendable {
    var handler: (URLRequest) throws -> (Int, [String: String], Data)
    private(set) var requests: [URLRequest] = []

    init(_ handler: @escaping (URLRequest) throws -> (Int, [String: String], Data)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, headers, body) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        return (body, response)
    }
}

private final class MemoryCache: ResponseCache, @unchecked Sendable {
    var entries: [String: CachedResponse] = [:]
    func entry(for path: String) -> CachedResponse? { entries[path] }
    func store(_ entry: CachedResponse, for path: String) { entries[path] = entry }
}

final class ClientTests: XCTestCase {
    let credentials = Credentials(email: "me@example.com", password: "secret")

    func testSendsBasicAuthAndDecodes() async throws {
        let body = try fixture("shows.json")
        let transport = StubTransport { _ in (200, [:], body) }
        let client = OroroClient(credentials: credentials, transport: transport)

        let shows = try await client.shows()
        XCTAssertEqual(shows.count, 2)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://front.ororo.tv/api/v2/shows")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"),
                       "Basic " + Data("me@example.com:secret".utf8).base64EncodedString())
    }

    func testRevalidatesCatalogWithETag() async throws {
        let body = try fixture("movies.json")
        let cache = MemoryCache()
        let transport = StubTransport { request in
            request.value(forHTTPHeaderField: "If-None-Match") == "W/\"v1\""
                ? (304, [:], Data())
                : (200, ["ETag": "W/\"v1\""], body)
        }
        let client = OroroClient(credentials: credentials, transport: transport, cache: cache)

        let first = try await client.movies()
        let second = try await client.movies()
        XCTAssertEqual(first, second)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertNil(transport.requests[0].value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "If-None-Match"), "W/\"v1\"")
    }

    func testFallsBackToMirrorAndRemembersIt() async throws {
        let body = try fixture("shows.json")
        let transport = StubTransport { request in
            if request.url?.host == "front.ororo.tv" { throw URLError(.cannotConnectToHost) }
            return (200, [:], body)
        }
        let client = OroroClient(credentials: credentials, transport: transport)

        _ = try await client.shows()
        _ = try await client.shows()
        XCTAssertEqual(transport.requests.map { $0.url!.host! },
                       ["front.ororo.tv", "front.ororo-mirror.tv", "front.ororo-mirror.tv"])
    }

    func testMapsStatusCodes() async {
        for (status, expected) in [(401, OroroError.unauthorized), (402, .limitReached),
                                   (404, .notFound), (500, .http(status: 500))] {
            let client = OroroClient(credentials: credentials,
                                     transport: StubTransport { _ in (status, [:], Data()) })
            do {
                _ = try await client.episode(id: 1)
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? OroroError, expected)
            }
        }
    }

    func testAllHostsDownIsANetworkError() async {
        let client = OroroClient(credentials: credentials,
                                 transport: StubTransport { _ in throw URLError(.notConnectedToInternet) })
        do {
            _ = try await client.shows()
            XCTFail("expected an error")
        } catch {
            guard case .network = error as? OroroError else { return XCTFail("got \(error)") }
        }
    }

    func testVerifyCredentialsTreats404AsSuccess() async throws {
        let good = OroroClient(credentials: credentials, transport: StubTransport { _ in (404, [:], Data()) })
        try await good.verifyCredentials()

        let bad = OroroClient(credentials: credentials, transport: StubTransport { _ in (401, [:], Data()) })
        do {
            try await bad.verifyCredentials()
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? OroroError, .unauthorized)
        }
    }

    func testPlaybackInfoForEpisode() async throws {
        let body = try fixture("episode_detail.json")
        let transport = StubTransport { _ in (200, [:], body) }
        let client = OroroClient(credentials: credentials, transport: transport)

        let info = try await client.playback(for: .episode(93825))
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/v2/episodes/93825")
        XCTAssertTrue(info.streamURL.absoluteString.hasSuffix("playlist_fmp4.m3u8?wmsAuthSign=TOKEN"))
        XCTAssertEqual(info.subtitle(for: "ru")?.url.lastPathComponent, "ru.vtt")
    }
}
