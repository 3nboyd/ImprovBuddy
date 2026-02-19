import SwiftUI

struct BPMDetectorView: View {
    @EnvironmentObject private var services: ServiceContainer

    @State private var listening = false
    @State private var errorText = ""

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Auto")
                    .font(.headline)
                Text(String(format: "%.1f BPM", services.bpmDetector.detectedBPM))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
            }

            VStack(spacing: 8) {
                Text("Tap")
                    .font(.headline)
                Text(String(format: "%.1f BPM", services.bpmDetector.tappedBPM))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Button("Tap Tempo") {
                    services.bpmDetector.tap()
                }
                .buttonStyle(.borderedProminent)
            }

            Button(listening ? "Stop Input" : "Start Input") {
                Task {
                    if listening {
                        services.audioManager.stop()
                        listening = false
                        errorText = ""
                    } else {
                        services.midiManager.start()
                        let granted = await services.audioManager.requestMicrophonePermission()
                        guard granted else {
                            errorText = "Microphone permission denied."
                            return
                        }

                        do {
                            try services.audioManager.start(recordAudio: false)
                            listening = true
                            errorText = ""
                        } catch {
                            errorText = error.localizedDescription
                        }
                    }
                }
            }
            .buttonStyle(.bordered)

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Reset") {
                services.bpmDetector.reset()
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding()
        .navigationTitle("BPM Detector")
        .onDisappear {
            if listening {
                services.audioManager.stop()
                listening = false
            }
        }
    }
}
