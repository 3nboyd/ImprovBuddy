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

            RecorderTabView()
                .tabItem {
                    Label("Recorder", systemImage: "waveform.badge.plus")
                }

            TheoryTabView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
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
