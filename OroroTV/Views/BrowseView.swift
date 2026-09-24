import OroroKit
import SwiftUI

/// Grid of every show or every movie, with genre filter and sort order.
struct BrowseView: View {
    enum Kind { case shows, movies }

    enum Sort: String, CaseIterable, Identifiable {
        case popular = "Popular"
        case recent = "Recent"
        case rating = "Top Rated"
        case name = "A–Z"
        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    let kind: Kind
    @State private var sort: Sort = .popular
    @State private var genre: String?

    private let columns = Array(repeating: GridItem(.fixed(250), spacing: 50), count: 6)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 30) {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 900)

                    Menu {
                        Button("All Genres") { genre = nil }
                        ForEach(allGenres, id: \.self) { name in
                            Button(name) { genre = name }
                        }
                    } label: {
                        Label(genre ?? "All Genres", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                LazyVGrid(columns: columns, spacing: 60) {
                    ForEach(titles) { PosterLink(title: $0) }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var allTitles: [Title] {
        switch kind {
        case .shows: return model.shows.map(Title.show)
        case .movies: return model.movies.map(Title.movie)
        }
    }

    private var allGenres: [String] {
        Array(Set(allTitles.flatMap(\.genres))).sorted()
    }

    private var titles: [Title] {
        let filtered = genre.map { name in allTitles.filter { $0.genres.contains(name) } } ?? allTitles
        switch sort {
        case .popular:
            return filtered.sorted { popularity($0) > popularity($1) }
        case .recent:
            return filtered.sorted { recency($0) > recency($1) }
        case .rating:
            return filtered.sorted { ($0.imdbRating ?? 0) > ($1.imdbRating ?? 0) }
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func popularity(_ title: Title) -> Double {
        switch title {
        case .show(let show): return Double(show.userPopularity ?? 0)
        // Movies carry no popularity in the list, so fall back to rating.
        case .movie(let movie): return movie.imdbRating ?? 0
        }
    }

    private func recency(_ title: Title) -> Int {
        switch title {
        case .show(let show): return show.newestVideo ?? 0
        case .movie(let movie): return movie.id
        }
    }
}
