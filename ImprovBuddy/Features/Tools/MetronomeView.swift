import SwiftUI

struct MetronomeView: View {
    @EnvironmentObject private var services: ServiceContainer

    @State private var bpm: Double = 120
    @State private var beatsPerBar = 4
    @State private var subdivision: MetronomeSubdivision = .quarter
    @State private var accentDownbeat = true
    @State private var swingMode = false
    @State private var dropoutProbability = 0.0
    @State private var soundSet: MetronomeSoundSet = .woodblock
    @State private var hapticsEnabled = false

    var body: some View {
        Form {
            Section("Tempo") {
                HStack {
                    Slider(value: $bpm, in: 30...320, step: 1)
                    Text("\(Int(bpm))")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                Stepper("Beats per bar: \(beatsPerBar)", value: $beatsPerBar, in: 2...12)

                Picker("Subdivision", selection: $subdivision) {
                    ForEach(MetronomeSubdivision.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                Toggle("Accent beat 1", isOn: $accentDownbeat)
                Toggle("Swing click mode", isOn: $swingMode)
            }

            Section("Sound") {
                Picker("Sound Set", selection: $soundSet) {
                    ForEach(MetronomeSoundSet.allCases) { set in
                        Text(set.rawValue.capitalized).tag(set)
                    }
                }

                VStack(alignment: .leading) {
                    Text("Random dropouts: \(Int(dropoutProbability * 100))%")
                    Slider(value: $dropoutProbability, in: 0...0.5, step: 0.05)
                }

                Toggle("Haptics", isOn: $hapticsEnabled)
            }

            Section {
                Button(services.metronomeEngine.isRunning ? "Stop" : "Start") {
                    applySettings()
                    if services.metronomeEngine.isRunning {
                        services.metronomeEngine.stop()
                    } else {
                        services.metronomeEngine.start()
                    }
                }
                .buttonStyle(.borderedProminent)

                if services.metronomeEngine.isRunning {
                    Text("Running step: \(services.metronomeEngine.currentStep)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Metronome")
        .onAppear {
            bpm = services.metronomeEngine.bpm
            beatsPerBar = services.metronomeEngine.beatsPerBar
            subdivision = services.metronomeEngine.subdivision
            accentDownbeat = services.metronomeEngine.accentDownbeat
            swingMode = services.metronomeEngine.swingMode
            dropoutProbability = services.metronomeEngine.dropoutProbability
            soundSet = services.metronomeEngine.soundSet
            hapticsEnabled = services.metronomeEngine.hapticsEnabled
        }
    }

    private func applySettings() {
        services.metronomeEngine.bpm = bpm
        services.metronomeEngine.beatsPerBar = beatsPerBar
        services.metronomeEngine.subdivision = subdivision
        services.metronomeEngine.accentDownbeat = accentDownbeat
        services.metronomeEngine.swingMode = swingMode
        services.metronomeEngine.dropoutProbability = dropoutProbability
        services.metronomeEngine.soundSet = soundSet
        services.metronomeEngine.hapticsEnabled = hapticsEnabled
        services.metronomeEngine.refreshSoundSet()
    }
}
