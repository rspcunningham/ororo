import OroroKit
import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [Title] = []

    private let columns = Array(repeating: GridItem(.fixed(250), spacing: 50), count: 6)

    var body: some View {
        ScrollView {
            if !query.isEmpty && results.isEmpty {
                Text("No results for “\(query)”")
                    .foregroundStyle(.secondary)
                    .padding(.top, 100)
            }
            LazyVGrid(columns: columns, spacing: 60) {
                ForEach(results) { PosterLink(title: $0) }
            }
            .padding(.horizontal, 20)
        }
        .searchable(text: $query, prompt: "Shows and movies")
        .task(id: query) {
            // Wait for a pause in typing.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            results = model.searchIndex.search(query)
        }
    }
}
