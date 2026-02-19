import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("Chord Forms")
                        .font(.headline)
                    Text("ImprovBuddy follows the chord form you provide. It does not require automatic chord detection.")

                    Text("Scoring")
                        .font(.headline)
                    Text("Time feel uses your onsets vs the session grid. Harmony uses your notes against the active chord symbol in the form.")

                    Text("Harmony States")
                        .font(.headline)
                    Text("Chord Tone, Tension, Approach, and Outside are measured continuously. Strong-beat chord-tone accuracy is weighted higher in report notes.")

                    Text("Form Alignment")
                        .font(.headline)
                    Text("If your position drifts from the form, use Jump to Bar or Restart Chorus to realign quickly.")
                }

                Group {
                    Text("Input Modes")
                        .font(.headline)
                    Text("MIDI mode is preferred for demos and piano. Mic mode uses pitch + onset detection and works for acoustic instruments.")

                    Text("Privacy")
                        .font(.headline)
                    Text("ImprovBuddy is local-first and runs analysis on-device. No login is required.")
                }
            }
            .padding()
        }
        .navigationTitle("How It Works")
    }
}
