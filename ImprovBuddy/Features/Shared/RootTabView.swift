import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.title) private var songs: [Song]

    var body: some View {
        TabView {
            CoachHomeView()
                .tabItem {
                    Label("Coach", systemImage: "music.mic")
                }

            SongsListView()
                .tabItem {
                    Label("Songs", systemImage: "music.note.list")
                }

            ToolsHomeView()
                .tabItem {
                    Label("Tools", systemImage: "metronome")
                }

            LibraryHomeView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .task {
            seedDemoSongsIfNeeded()
        }
    }

    private func seedDemoSongsIfNeeded() {
        guard songs.isEmpty else { return }
        Song.demoSongs().forEach(modelContext.insert)
        try? modelContext.save()
    }
}
