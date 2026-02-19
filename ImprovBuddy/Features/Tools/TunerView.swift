import SwiftUI

struct TunerView: View {
    @EnvironmentObject private var services: ServiceContainer

    @State private var isListening = false

    var body: some View {
        VStack(spacing: 20) {
            Text(services.tunerEngine.noteName)
                .font(.system(size: 92, weight: .bold, design: .rounded))

            Text(String(format: "%+.1f cents", services.tunerEngine.cents))
                .font(.title2.monospacedDigit())
                .foregroundStyle(colorForCents(services.tunerEngine.cents))

            TunerNeedle(cents: services.tunerEngine.cents)
                .frame(height: 40)

            Text("Confidence: \(String(format: "%.0f%%", services.tunerEngine.confidence * 100))")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Text("A4")
                Slider(value: $services.tunerEngine.a4ReferenceHz, in: 430...450, step: 0.5)
                Text(String(format: "%.1f Hz", services.tunerEngine.a4ReferenceHz))
                    .frame(width: 70)
            }
            .padding(.horizontal)

            Button(isListening ? "Stop Listening" : "Start Listening") {
                Task {
                    if isListening {
                        services.audioManager.stop()
                        isListening = false
                    } else {
                        services.midiManager.start()
                        _ = await services.audioManager.requestMicrophonePermission()
                        if services.audioManager.micPermissionGranted {
                            try? services.audioManager.start(recordAudio: false)
                        }
                        isListening = true
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
        .navigationTitle("Tuner")
        .onDisappear {
            if isListening {
                services.audioManager.stop()
                isListening = false
            }
        }
    }

    private func colorForCents(_ cents: Double) -> Color {
        switch abs(cents) {
        case 0..<5: .green
        case 5..<15: .yellow
        default: .red
        }
    }
}

private struct TunerNeedle: View {
    let cents: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let normalized = max(-1, min(1, cents / 50))
            let x = width * (0.5 + (normalized * 0.45))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.gray.opacity(0.2))
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .position(x: width / 2, y: geometry.size.height / 2)
                Circle()
                    .fill(.primary)
                    .frame(width: 14, height: 14)
                    .position(x: x, y: geometry.size.height / 2)
            }
        }
    }
}
