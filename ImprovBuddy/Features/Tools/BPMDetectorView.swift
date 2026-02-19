import SwiftUI

struct BPMDetectorView: View {
    @EnvironmentObject private var services: ServiceContainer

    @State private var listening = false

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
                    } else {
                        services.midiManager.start()
                        _ = await services.audioManager.requestMicrophonePermission()
                        if services.audioManager.micPermissionGranted {
                            try? services.audioManager.start(recordAudio: false)
                        }
                        listening = true
                    }
                }
            }
            .buttonStyle(.bordered)

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
