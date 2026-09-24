import OroroKit
import SwiftUI

struct MovieDetailView: View {
    @Environment(AppModel.self) private var model
    let movie: Movie

    var body: some View {
        let media = MediaRef.movie(movie.id)
        let resume = model.library.record(for: media)?.resumePosition

        ZStack(alignment: .bottomLeading) {
            Backdrop(url: movie.backdropURL ?? movie.posterURL)

            HStack(alignment: .bottom, spacing: 60) {
                PosterImage(url: movie.posterURL, width: 320)
                VStack(alignment: .leading, spacing: 24) {
                    Text(movie.name).font(.largeTitle).bold()
                    Text(metadataLine(year: movie.year, genres: movie.genres,
                                      rating: movie.imdbRating, minutes: movie.length))
                        .foregroundStyle(.secondary)
                    Text(movie.desc)
                        .lineLimit(5)
                        .frame(maxWidth: 1100, alignment: .leading)

                    HStack(spacing: 30) {
                        Button {
                            model.play(movie)
                        } label: {
                            Label(resume == nil ? "Play" : "Resume", systemImage: "play.fill")
                        }
                        if resume != nil {
                            Button {
                                model.play(movie, fromStart: true)
                            } label: {
                                Label("Start Over", systemImage: "gobackward")
                            }
                        }
                        Button {
                            model.library.toggleSaved(media)
                        } label: {
                            Label("My List", systemImage: model.library.isSaved(media) ? "checkmark" : "plus")
                        }
                    }
                }
            }
            .padding(80)
        }
    }
}
