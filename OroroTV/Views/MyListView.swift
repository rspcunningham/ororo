import OroroKit
import SwiftUI

struct MyListView: View {
    @Environment(AppModel.self) private var model

    private let columns = Array(repeating: GridItem(.fixed(250), spacing: 50), count: 6)

    var body: some View {
        let titles = model.library.savedItems.compactMap(model.title(for:))
        ScrollView {
            if titles.isEmpty {
                Text("Add shows and movies to My List from their detail screens.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 100)
            }
            LazyVGrid(columns: columns, spacing: 60) {
                ForEach(titles) { title in
                    PosterLink(title: title)
                        .contextMenu {
                            Button("Remove from My List", role: .destructive) {
                                model.library.toggleSaved(title.id)
                            }
                        }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
