import SwiftUI

struct PracticeSandboxView: View {
    @EnvironmentObject private var services: ServiceContainer

    @State private var engine: PracticeSandboxEngine?
    @State private var inputMode: InputMode = .both
    @State private var targetBPM: Double = 100
    @State private var errorText = ""

    var body: some View {
        VStack(spacing: 18) {
            if let engine {
                Text(String(format: "%.1f BPM", engine.liveBPM))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                Text(String(format: "Error: %.1f ms", engine.latestErrorMs))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(engine.driftState == .stable ? .green : .orange)

                Text(engine.driftState == .stable ? "Stable" : "Drifting")
                    .font(.headline)
            }

            Picker("Input Mode", selection: $inputMode) {
                ForEach(InputMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Slider(value: $targetBPM, in: 40...300, step: 1)
                Text("\(Int(targetBPM))")
                    .frame(width: 44)
                    .monospacedDigit()
            }

            HStack {
                Button(engine?.isRunning == true ? "Stop" : "Start") {
                    toggleSession()
                }
                .buttonStyle(.borderedProminent)

                Button("Reset") {
                    engine?.stop()
                }
                .buttonStyle(.bordered)
            }

            Text("Sandbox mode focuses on rhythm and pocket only. Harmony scoring is disabled.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Practice Sandbox")
        .onAppear {
            if engine == nil {
                engine = PracticeSandboxEngine(eventBus: services.eventBus)
            }
        }
        .onDisappear {
            engine?.stop()
            services.audioManager.stop()
        }
    }

    private func toggleSession() {
        guard let engine else { return }

        if engine.isRunning {
            engine.stop()
            services.audioManager.stop()
            errorText = ""
            return
        }

        engine.inputMode = inputMode
        engine.targetBPM = targetBPM

        Task {
            if inputMode == .midi || inputMode == .both {
                services.midiManager.start()
            }

            if inputMode == .mic || inputMode == .both {
                let granted = await services.audioManager.requestMicrophonePermission()
                guard granted else {
                    errorText = "Microphone permission denied."
                    return
                }

                do {
                    try services.audioManager.start(recordAudio: false)
                } catch {
                    errorText = error.localizedDescription
                    return
                }
            }

            engine.start()
            errorText = ""
        }
    }
}
