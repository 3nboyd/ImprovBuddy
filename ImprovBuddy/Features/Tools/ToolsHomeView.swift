import SwiftUI

struct ToolsHomeView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Metronome") {
                    MetronomeView()
                }

                NavigationLink("Tuner") {
                    TunerView()
                }

                NavigationLink("BPM Detector") {
                    BPMDetectorView()
                }

                NavigationLink("Practice Sandbox") {
                    PracticeSandboxView()
                }
            }
            .navigationTitle("Tools")
        }
    }
}
