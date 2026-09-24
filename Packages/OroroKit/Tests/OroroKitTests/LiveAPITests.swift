import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OroroKit

/// Runs against the real API. Skipped unless credentials are supplied:
///
///     ORORO_EMAIL=you@example.com ORORO_PASSWORD=... swift test --filter LiveAPITests
final class LiveAPITests: XCTestCase {
    private func makeClient() throws -> OroroClient {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["ORORO_EMAIL"], let password = env["ORORO_PASSWORD"] else {
            throw XCTSkip("Set ORORO_EMAIL and ORORO_PASSWORD to run live API tests")
        }
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("ororo-live-\(UUID())")
        return OroroClient(credentials: Credentials(email: email, password: password),
                           cache: FileResponseCache(directory: cacheDir))
    }

    func testCatalogPlaybackAndSubtitles() async throws {
        let client = try makeClient()
        try await client.verifyCredentials()

        let shows = try await client.shows()
        let movies = try await client.movies()
        XCTAssertGreaterThan(shows.count, 1000)
        XCTAssertGreaterThan(movies.count, 1000)
        // Second fetch should be served by a 304 from the ETag cache.
        let again = try await client.movies()
        XCTAssertEqual(again.count, movies.count)

        let index = SearchIndex(shows: shows, movies: movies)
        XCTAssertFalse(index.search("the").isEmpty)

        let popular = try XCTUnwrap(shows.max { ($0.userPopularity ?? 0) < ($1.userPopularity ?? 0) })
        let detail = try await client.show(id: popular.id)
        let episode = try XCTUnwrap(detail.orderedEpisodes.last)
        let playback = try await client.playback(for: .episode(episode.id))
        XCTAssertTrue(playback.streamURL.absoluteString.contains(".m3u8"))

        let movie = try XCTUnwrap(movies.first)
        _ = try await client.playback(for: .movie(movie.id))

        if let subtitle = playback.subtitle(for: "en") ?? playback.subtitles.first {
            let (data, _) = try await URLSessionTransport().send(URLRequest(url: subtitle.url))
            let track = SubtitleTrack(webVTT: String(decoding: data, as: UTF8.self))
            XCTAssertGreaterThan(track.cues.count, 10)
        }
    }

    func testRejectsWrongPassword() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["ORORO_EMAIL"] != nil else { throw XCTSkip("live tests disabled") }
        let client = OroroClient(credentials: Credentials(email: "nobody@example.com", password: "wrong"))
        do {
            try await client.verifyCredentials()
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? OroroError, .unauthorized)
        }
    }
}
