import OroroKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .signedOut:
                LoginView()
            case .loading:
                ProgressView("Loading catalog…")
            case .failed(let message):
                VStack(spacing: 40) {
                    Text("Couldn't load Ororo").font(.title2)
                    Text(message).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await model.loadCatalog() } }
                    Button("Sign Out", role: .destructive) { model.signOut() }
                }
            case .ready:
                MainTabs()
            }
        }
        .fullScreenCover(item: $model.nowPlaying) { request in
            PlayerScreen(request: request)
        }
    }
}

private struct MainTabs: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView().withTitleDestinations() }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack { SearchView().withTitleDestinations() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            NavigationStack { BrowseView(kind: .shows).withTitleDestinations() }
                .tabItem { Label("TV Shows", systemImage: "tv") }
            NavigationStack { BrowseView(kind: .movies).withTitleDestinations() }
                .tabItem { Label("Movies", systemImage: "film") }
            NavigationStack { MyListView().withTitleDestinations() }
                .tabItem { Label("My List", systemImage: "plus.square.on.square") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

extension View {
    /// Pushes the right detail screen for a tapped show or movie.
    func withTitleDestinations() -> some View {
        navigationDestination(for: Title.self) { title in
            switch title {
            case .show(let show): ShowDetailView(show: show)
            case .movie(let movie): MovieDetailView(movie: movie)
            }
        }
    }
}
