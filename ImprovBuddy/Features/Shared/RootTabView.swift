import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: ServiceContainer
    @Query(sort: \Song.title) private var songs: [Song]
    @AppStorage("app.didRequestMicPermissionAtLaunch") private var didRequestMicPermissionAtLaunch = false

    var body: some View {
        TabView {
            CoachHomeView()
                .tabItem {
                    Label("Coach", systemImage: "music.mic")
                }

            RecorderTabView()
                .tabItem {
                    Label("Recorder", systemImage: "waveform.badge.plus")
                }

            ToolsHomeView()
                .tabItem {
                    Label("Tools", systemImage: "metronome")
                }

            TheoryTabView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .task {
            seedDemoSongsIfNeeded()
            await requestMicrophonePermissionIfNeeded()
        }
    }

    private func seedDemoSongsIfNeeded() {
        guard songs.isEmpty else { return }
        Song.demoSongs().forEach(modelContext.insert)
        try? modelContext.save()
    }

    @MainActor
    private func requestMicrophonePermissionIfNeeded() async {
        guard !didRequestMicPermissionAtLaunch else { return }
        didRequestMicPermissionAtLaunch = true
        _ = await services.audioManager.requestMicrophonePermission()
    }
}
