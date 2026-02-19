import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var services: ServiceContainer

    @State private var selectedInputMode: InputMode = .both

    var body: some View {
        Form {
            Section("Input") {
                Picker("Preferred Input", selection: $selectedInputMode) {
                    ForEach(InputMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Text("Audio route: \(services.audioManager.currentRouteName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if services.midiManager.sources.isEmpty {
                    Text("No MIDI sources detected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(services.midiManager.sources) { source in
                        HStack {
                            Text(source.name)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { services.midiManager.connectedSourceIDs.contains(source.id) },
                                set: { _ in services.midiManager.toggleConnection(for: source) }
                            ))
                            .labelsHidden()
                        }
                    }
                }

                Button("Refresh MIDI Devices") {
                    services.midiManager.refreshSources()
                }
            }

            Section("Calibration") {
                HStack {
                    Text("A4 Reference")
                    Slider(value: $appEnvironment.preferredA4, in: 430...450, step: 0.5)
                    Text(String(format: "%.1f", appEnvironment.preferredA4))
                        .frame(width: 52)
                }

                HStack {
                    Text("Analysis Sensitivity")
                    Slider(value: $appEnvironment.analysisSensitivity, in: 0...1)
                }

                Text("Temperament: Equal (MVP)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Neon Accent", selection: $appEnvironment.neonAccent) {
                    ForEach(NeonAccent.allCases) { accent in
                        HStack {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 10, height: 10)
                            Text(accent.displayName)
                        }
                        .tag(accent)
                    }
                }
            }

            Section("Accessibility") {
                Toggle("High Contrast Mode", isOn: $appEnvironment.highContrastModeEnabled)
                Toggle("Show Labs (Beta)", isOn: $appEnvironment.showLabsBeta)
            }

            Section("Help") {
                NavigationLink("How ImprovBuddy Scores") {
                    HelpView()
                }

                NavigationLink("Debug Test Lab") {
                    DebugTestLabView()
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            services.midiManager.refreshSources()
            selectedInputMode = .both
        }
    }
}
