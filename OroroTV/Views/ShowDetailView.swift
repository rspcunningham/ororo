import OroroKit
import SwiftUI

struct ShowDetailView: View {
    @Environment(AppModel.self) private var model
    let show: Show
    @State private var detail: ShowDetail?
    @State private var season: Int?
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Backdrop(url: show.backdropURL ?? show.posterURL)

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    if let detail {
                        seasonPicker(detail)
                        episodeList(detail)
                    } else if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else {
                        ProgressView()
                    }
                }
                .padding(60)
            }
        }
        .task {
            do {
                let loaded = try await model.showDetail(id: show.id)
                detail = loaded
                season = model.library.nextEpisode(in: loaded)?.season ?? loaded.seasonNumbers.first
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(show.name).font(.largeTitle).bold()
            Text(metadataLine(year: show.year, genres: show.genres, rating: show.imdbRating, minutes: show.length))
                .foregroundStyle(.secondary)
            Text(show.desc)
                .lineLimit(4)
                .frame(maxWidth: 1100, alignment: .leading)

            HStack(spacing: 30) {
                if let detail, let next = model.library.nextEpisode(in: detail) {
                    Button {
                        model.play(next, of: show)
                    } label: {
                        Label(playLabel(for: next), systemImage: "play.fill")
                    }
                }
                let saved = model.library.isSaved(.show(show.id))
                Button {
                    model.library.toggleSaved(.show(show.id))
                } label: {
                    Label("My List", systemImage: saved ? "checkmark" : "plus")
                }
            }
        }
    }

    private func playLabel(for episode: Episode) -> String {
        guard let record = model.library.lastWatchedEpisode(ofShow: show.id) else {
            return "Play \(episode.code)"
        }
        return record.media == .episode(episode.id) ? "Resume \(episode.code)" : "Play Next \(episode.code)"
    }

    @ViewBuilder
    private func seasonPicker(_ detail: ShowDetail) -> some View {
        if detail.seasonNumbers.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    ForEach(detail.seasonNumbers, id: \.self) { number in
                        Button { season = number } label: {
                            // The white tint doesn't change the label color, so set it here.
                            if number == season {
                                Text("Season \(number)").foregroundStyle(.black)
                            } else {
                                Text("Season \(number)")
                            }
                        }
                        .tint(number == season ? .white : nil)
                        .fontWeight(number == season ? .bold : .regular)
                    }
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
    }

    private func episodeList(_ detail: ShowDetail) -> some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(detail.episodes(inSeason: season ?? detail.seasonNumbers.first ?? 1)) { episode in
                EpisodeRow(show: show, episode: episode)
            }
        }
    }
}

private struct EpisodeRow: View {
    @Environment(AppModel.self) private var model
    let show: Show
    let episode: Episode

    var body: some View {
        let media = MediaRef.episode(episode.id)
        let record = model.library.record(for: media)

        Button {
            model.play(episode, of: show)
        } label: {
            HStack(alignment: .top, spacing: 30) {
                Text(episode.number)
                    .font(.title2).bold()
                    .frame(width: 80)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(episode.displayName).font(.headline)
                        if record?.isFinished == true {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    if let plot = episode.plot, !plot.isEmpty {
                        Text(plot).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if let record, !record.isFinished, record.progress > 0 {
                        ProgressLine(progress: record.progress).frame(width: 400)
                    }
                }
                Spacer()
                if let airdate = episode.airdate {
                    Text(airdate).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .buttonStyle(.card)
        .contextMenu {
            if record?.isFinished == true {
                Button("Mark as Unwatched") { model.library.markUnwatched(media) }
            } else {
                Button("Mark as Watched") {
                    model.library.markWatched(media, showID: show.id, season: episode.season,
                                              episodeNumber: episode.number)
                }
            }
            if record != nil {
                Button("Play from Beginning") { model.play(episode, of: show, fromStart: true) }
            }
        }
    }
}
