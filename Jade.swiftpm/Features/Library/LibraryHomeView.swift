import SwiftUI

struct LibraryHomeView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Idea Recorder") {
                    IdeaRecorderView()
                }

                NavigationLink("Theory Library") {
                    TheoryLibraryView()
                }

                if appEnvironment.showLabsBeta {
                    Section("Labs (Beta)") {
                        NavigationLink("Lick Cards") {
                            LickCardsLabsView()
                        }
                    }
                }
            }
            .navigationTitle("Library")
        }
    }
}
