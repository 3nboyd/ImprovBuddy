import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("Songs Workspace")
                        .font(.headline)
                    Text("Jade is optimized around real sheet music. Import PDFs or images, attach multiple pages, and swipe through pages while keeping Tools available.")

                    Text("Tools + Global Overlays")
                        .font(.headline)
                    Text("Mini Tuner and Mini BPM overlays mirror the same engines used in Tools. Any change to tempo, start/stop, or tuning reflects across tabs.")

                    Text("Metronome")
                        .font(.headline)
                    Text("Tap tempo, meter, subdivision, count-in, and sound are live controls. If count-in is enabled, playback starts after the visual count-in completes.")

                    Text("Tuner")
                        .font(.headline)
                    Text("Pitch display uses a flat-to-sharp gradient with a moving marker and note/cents readout. Hold on the pitch area to audition/sustain target tones.")
                }

                Group {
                    Text("Idea Recorder")
                        .font(.headline)
                    Text("Audio ideas save locally with auto-incrementing take names. Swipe left to delete, swipe right to pin, and use inline speed/transpose controls during playback.")

                    Text("Privacy")
                        .font(.headline)
                    Text("Jade is local-first. Audio analysis, tuner, metronome, and library metadata processing run on-device. No account is required.")
                }
            }
            .padding()
        }
        .navigationTitle("Jade Help")
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider().opacity(0.2)
            }
        }
    }
}
