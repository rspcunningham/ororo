import OroroKit
import SwiftUI

/// Poster with a focus-lift card effect. Tapping pushes the detail screen.
struct PosterLink: View {
    let title: Title
    var width: CGFloat = 250

    var body: some View {
        NavigationLink(value: title) {
            PosterImage(url: title.posterURL, width: width)
        }
        .buttonStyle(.card)
        .accessibilityLabel(title.name)
    }
}

struct PosterImage: View {
    let url: URL?
    var width: CGFloat = 250

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Rectangle().fill(.gray.opacity(0.25))
                    .overlay(Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary))
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipped()
    }
}

/// Wide backdrop behind detail screens, fading into the background.
struct Backdrop: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.clear
        }
        .overlay(
            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.95)],
                           startPoint: .top, endPoint: .bottom)
        )
        .ignoresSafeArea()
    }
}

/// A titled, horizontally scrolling row of posters.
struct Shelf<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.title3).bold()
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) { content() }
                    .padding(.vertical, 30)
            }
            .scrollClipDisabled()
        }
    }
}

struct ProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(.red).frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}

/// "2011 · Comedy, Crime · ★ 7.8 · 60 min"
func metadataLine(year: String, genres: [String], rating: Double?, minutes: Int?) -> String {
    var parts = [year]
    if !genres.isEmpty { parts.append(genres.prefix(3).joined(separator: ", ")) }
    if let rating { parts.append(String(format: "★ %.1f", rating)) }
    if let minutes, minutes > 0 { parts.append("\(minutes) min") }
    return parts.joined(separator: " · ")
}

func languageName(_ code: String) -> String {
    Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
}
