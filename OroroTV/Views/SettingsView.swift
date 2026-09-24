import OroroKit
import SwiftUI

enum SubtitleSettings {
    static let primaryKey = "subtitles.primary"
    static let secondaryKey = "subtitles.secondary"
    /// Languages Ororo commonly has subtitles in.
    static let languages = ["en", "ru", "es", "it", "pl", "pt", "tr", "de", "fr", "cs", "uk", "nl", "el", "ro"]
    static let off = ""
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SubtitleSettings.primaryKey) private var primary = "en"
    @AppStorage(SubtitleSettings.secondaryKey) private var secondary = SubtitleSettings.off
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Subtitles") {
                Picker("Subtitles", selection: $primary) {
                    Text("Off").tag(SubtitleSettings.off)
                    ForEach(SubtitleSettings.languages, id: \.self) { Text(languageName($0)).tag($0) }
                }
                Picker("Second Subtitles", selection: $secondary) {
                    Text("Off").tag(SubtitleSettings.off)
                    ForEach(SubtitleSettings.languages, id: \.self) { Text(languageName($0)).tag($0) }
                }
                Text("Second subtitles show above the first, for learning a language alongside your own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Button("Clear Watch History", role: .destructive) { confirmClear = true }
            }

            Section("Account") {
                if let email = model.email {
                    LabeledContent("Signed in as", value: email)
                }
                Button("Refresh Catalog") { Task { await model.loadCatalog() } }
                Button("Sign Out", role: .destructive) { model.signOut() }
            }
        }
        .confirmationDialog("Clear your watch history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.library.clearHistory() }
        }
    }
}
