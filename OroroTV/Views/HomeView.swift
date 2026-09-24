import OroroKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 50) {
                let continueRecords = model.library.continueWatching()
                if !continueRecords.isEmpty {
                    Shelf(title: "Continue Watching") {
                        ForEach(continueRecords, id: \.media) { record in
                            ContinueCard(record: record)
                        }
                    }
                }

                let saved = model.library.savedItems.compactMap(model.title(for:))
                if !saved.isEmpty {
                    titleShelf("My List", saved)
                }

                titleShelf("New Episodes",
                           model.shows.sorted { ($0.newestVideo ?? 0) > ($1.newestVideo ?? 0) }.prefix(30).map(Title.show))
                titleShelf("Popular Shows",
                           model.shows.sorted { ($0.userPopularity ?? 0) > ($1.userPopularity ?? 0) }.prefix(30).map(Title.show))
                // Higher IDs were added more recently; the list has no "added" date.
                titleShelf("Recently Added Movies",
                           model.movies.sorted { $0.id > $1.id }.prefix(30).map(Title.movie))
                titleShelf("Top Rated Movies",
                           model.movies.filter { $0.year >= "2000" }
                               .sorted { ($0.imdbRating ?? 0) > ($1.imdbRating ?? 0) }.prefix(30).map(Title.movie))
                ForEach(["Comedy", "Crime", "Sci-Fi", "Documentary", "Animation"], id: \.self) { genre in
                    titleShelf(genre,
                               model.movies.filter { $0.genres.contains(genre) }
                                   .sorted { $0.id > $1.id }.prefix(30).map(Title.movie))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func titleShelf(_ name: String, _ titles: [Title]) -> some View {
        if !titles.isEmpty {
            Shelf(title: name) {
                ForEach(titles) { PosterLink(title: $0) }
            }
        }
    }
}

/// A Continue Watching entry. Selecting it plays straight away, Netflix-style.
private struct ContinueCard: View {
    @Environment(AppModel.self) private var model
    let record: WatchRecord
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: resume) {
                VStack(spacing: 0) {
                    PosterImage(url: posterURL)
                    ProgressLine(progress: record.isFinished ? 1 : record.progress)
                }
            }
            .buttonStyle(.card)
            .contextMenu {
                Button("Remove from Continue Watching", role: .destructive) {
                    model.library.removeFromHistory(record.groupKey)
                }
            }

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 250, alignment: .leading)
        }
        .alert("Can't play", isPresented: Binding(get: { errorMessage != nil },
                                                  set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var groupTitle: Title? { model.title(for: record.groupKey) }
    private var posterURL: URL? { groupTitle?.posterURL }

    private var caption: String {
        let name = groupTitle?.name ?? ""
        if record.showID != nil {
            if record.isFinished { return "\(name) · Next episode" }
            let code = String(format: "S%dE%@", record.season ?? 0, record.episodeNumber ?? "?")
            return "\(name) · \(code)"
        }
        let minutesLeft = Int((record.duration - record.position) / 60)
        return "\(name) · \(minutesLeft) min left"
    }

    private func resume() {
        switch record.groupKey {
        case .movie(let id):
            if let movie = model.movie(id: id) { model.play(movie) }
        case .show(let id):
            Task {
                do {
                    let started = try await model.continueShow(id: id)
                    if !started {
                        // Finished the whole show; nothing left to continue.
                        model.library.removeFromHistory(.show(id))
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .episode:
            break
        }
    }
}
