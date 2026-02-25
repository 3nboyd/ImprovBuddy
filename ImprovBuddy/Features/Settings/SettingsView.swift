import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var services: ServiceContainer

    @State private var selectedInputMode: InputMode = .both
    @AppStorage(TheoryPlaybackSound.defaultsKey) private var theoryPlaybackSoundRawValue = TheoryPlaybackSound.defaultValue.rawValue

    var body: some View {
        Form {
            Section("About") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Jade")
                        .font(.title3.weight(.bold))
                    Text("The Live Musician's Best Friend")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(appEnvironment.accentColor)
                }
                .padding(.vertical, 2)
            }

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
                    Text("Analysis Sensitivity")
                    Slider(value: $appEnvironment.analysisSensitivity, in: 0...1)
                }
            }

            Section("Theory Library") {
                Picker("Playback Sound", selection: $theoryPlaybackSoundRawValue) {
                    ForEach(TheoryPlaybackSound.allCases) { sound in
                        Text(sound.displayName).tag(sound.rawValue)
                    }
                }

                Text("Used by Play Scale, Play Chord, and Play Arpeggio.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Metronome") {
                Toggle(
                    "Different Sound for Subdivisions",
                    isOn: Binding(
                        get: { services.toolsSettings.metronome.subdivisionUsesAlternateClick },
                        set: { newValue in
                            var settings = services.toolsSettings.metronome
                            settings.subdivisionUsesAlternateClick = newValue
                            services.toolsSettings.metronome = settings
                        }
                    )
                )

                Text("When enabled, subdivision clicks use a distinct timbre from the main beat.")
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

            Section("Recorder") {
                NavigationLink("Recorder Recently Deleted") {
                    RecorderRecentlyDeletedView()
                }

                Text("Recover ideas you deleted with a swipe in Idea Recorder.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Help") {
                NavigationLink("How Jade Scores") {
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

private struct RecorderRecentlyDeletedView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Query(sort: \LibraryItem.updatedAt, order: .reverse) private var libraryItems: [LibraryItem]

    @State private var selectedIDs = Set<UUID>()
    @State private var statusText = ""

    private var deletedRecorderItems: [LibraryItem] {
        libraryItems.filter { $0.type == .ideaSnippet && $0.isRecorderDeleted }
    }

    private var allSelected: Bool {
        !deletedRecorderItems.isEmpty && deletedRecorderItems.allSatisfy { selectedIDs.contains($0.id) }
    }

    var body: some View {
        List {
            if deletedRecorderItems.isEmpty {
                Text("No recently deleted recorder ideas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(deletedRecorderItems) { item in
                    HStack(spacing: 10) {
                        Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(selectedIDs.contains(item.id) ? appEnvironment.accentColor : .secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Button("Recover") {
                            recover(item)
                        }
                        .buttonStyle(.bordered)
                        .tint(appEnvironment.accentColor)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleSelection(for: item.id)
                    }
                }
            }
        }
        .navigationTitle("Recorder Recently Deleted")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(allSelected ? "Clear" : "Select All") {
                    if allSelected {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = Set(deletedRecorderItems.map(\.id))
                    }
                }
                .disabled(deletedRecorderItems.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !deletedRecorderItems.isEmpty {
                VStack(spacing: 8) {
                    Button {
                        recoverSelected()
                    } label: {
                        Text("Recover Selected (\(selectedIDs.count))")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appEnvironment.accentColor)
                    .disabled(selectedIDs.isEmpty)

                    if !statusText.isEmpty {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider().opacity(0.2)
                }
            }
        }
        .onChange(of: deletedRecorderItems.map(\.id)) { _, ids in
            selectedIDs = selectedIDs.intersection(Set(ids))
        }
    }

    private func toggleSelection(for id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func recoverSelected() {
        let targets = deletedRecorderItems.filter { selectedIDs.contains($0.id) }
        guard !targets.isEmpty else { return }

        for item in targets {
            item.isRecorderDeleted = false
            item.updatedAt = .now
        }
        try? modelContext.save()

        statusText = "Recovered \(targets.count) idea\(targets.count == 1 ? "" : "s")."
        selectedIDs.removeAll()
    }

    private func recover(_ item: LibraryItem) {
        item.isRecorderDeleted = false
        item.updatedAt = .now
        try? modelContext.save()
        selectedIDs.remove(item.id)
        statusText = "Recovered \(item.title)."
    }
}
