import SwiftUI

struct TheoryLibraryView: View {
    @EnvironmentObject private var services: ServiceContainer
    @StateObject private var synth = SimpleSynth()

    @State private var selectedChordID = ""
    @State private var selectedKeyName = TheoryKey.defaultKey.name
    @State private var selectedInstrument: TheoryInstrumentTransposition = .concert
    @State private var selectedClef: TheoryClef = .treble
    @State private var selectedTier: TheoryTier = .core
    @State private var selectedSortMode: TheorySortMode = .relevance
    @State private var selectedFunctionFilter = "All"
    @State private var selectedFamilyFilter = "All"
    @State private var feedbackMessage = ""

    private var functionOptions: [String] {
        ["All"] + TheoryFunctionTag.allCases.map(\.displayName)
    }

    private var context: TheoryContext {
        TheoryContext(
            concertKeyName: selectedKeyName,
            instrument: selectedInstrument,
            clef: selectedClef,
            preferredTier: selectedTier,
            scoringUsesScaleAwareness: true
        )
    }

    private var functionFilter: TheoryFunctionTag? {
        TheoryFunctionTag.allCases.first(where: { $0.displayName == selectedFunctionFilter })
    }

    private var chordChoices: [TheoryChordDefinition] {
        services.theoryResolver.availableChordDefinitions(
            tier: selectedTier,
            functionFilter: functionFilter,
            familyFilter: selectedFamilyFilter
        )
    }

    private var currentOptions: [TheoryResolvedOption] {
        services.theoryResolver.options(
            forChordID: selectedChordID,
            context: context,
            functionFilter: functionFilter,
            sortMode: selectedSortMode
        )
    }

    private var primaryOption: TheoryResolvedOption? {
        currentOptions.first
    }

    private var rootPitchClass: Int {
        TheoryKey.byName(selectedKeyName).rootPitchClass
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controlsSection
                chordPickerSection
                resultsSection
            }
            .padding()
        }
        .navigationTitle("Theory Library")
        .onAppear {
            syncSelectedChord()
        }
        .onChange(of: selectedTier) { _, _ in syncSelectedChord() }
        .onChange(of: selectedFunctionFilter) { _, _ in syncSelectedChord() }
        .onChange(of: selectedFamilyFilter) { _, _ in syncSelectedChord() }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context")
                .font(.headline)

            HStack {
                Picker("Key", selection: $selectedKeyName) {
                    ForEach(TheoryKey.all, id: \.name) { key in
                        Text(key.name).tag(key.name)
                    }
                }
                .pickerStyle(.menu)

                Picker("Instrument", selection: $selectedInstrument) {
                    ForEach(TheoryInstrumentTransposition.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Picker("Clef", selection: $selectedClef) {
                    ForEach(TheoryClef.allCases) { clef in
                        Text(clef.displayName).tag(clef)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Tier", selection: $selectedTier) {
                    ForEach(TheoryTier.allCases) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Picker("Function", selection: $selectedFunctionFilter) {
                    ForEach(functionOptions, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .pickerStyle(.menu)

                Picker("Family", selection: $selectedFamilyFilter) {
                    ForEach(services.theoryResolver.availableFamilies(), id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .pickerStyle(.menu)

                Picker("Sort", selection: $selectedSortMode) {
                    ForEach(TheorySortMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var chordPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chord / Function")
                .font(.headline)

            if chordChoices.isEmpty {
                Text("No chord definitions for current filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Chord", selection: $selectedChordID) {
                    ForEach(chordChoices) { chord in
                        Text(chord.name).tag(chord.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if let option = primaryOption {
            let primaryNotes = services.theoryResolver.renderedScaleNotes(
                scale: option.primaryScale,
                rootPitchClass: rootPitchClass,
                context: context
            )
            let primaryPitchClasses = Set(primaryNotes.map(\.spelled.pitchClass))
            let noteLabel = primaryNotes.map { $0.spelled.name }.joined(separator: "  ")

            VStack(alignment: .leading, spacing: 10) {
                Text("Best Match")
                    .font(.headline)

                Text(option.primaryScale.name)
                    .font(.title3.bold())

                Text(option.recommendation.rationale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let guide = option.guideToneRule {
                    Text("Guide tones: \(guide.description)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Notes: \(noteLabel)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)

                StaffView(notes: primaryNotes, clef: selectedClef)
                PianoStripView(highlightedPitchClasses: primaryPitchClasses)

                HStack {
                    Button("Audition Scale") {
                        synth.playMIDINotes(primaryNotes.map(\.spelled.midi))
                    }
                    .buttonStyle(.bordered)

                    if let firstArp = option.arpeggios.first {
                        Button("Audition Arpeggio") {
                            let arpNotes = services.theoryResolver.renderedArpeggioNotes(
                                arpeggio: firstArp,
                                rootPitchClass: rootPitchClass,
                                context: context
                            )
                            synth.playMIDINotes(arpNotes.map(\.spelled.midi))
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Send to Drill") {
                        queueDrill(from: option)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

            if !option.alternatives.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Alternatives")
                        .font(.headline)

                    ForEach(option.alternatives, id: \.id) { scale in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scale.name)
                                Text(scale.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Audition") {
                                let notes = services.theoryResolver.renderedScaleNotes(
                                    scale: scale,
                                    rootPitchClass: rootPitchClass,
                                    context: context
                                )
                                synth.playMIDINotes(notes.map(\.spelled.midi))
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }

            if !feedbackMessage.isEmpty {
                Text(feedbackMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No recommendations for this chord in the current context.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func queueDrill(from option: TheoryResolvedOption) {
        for id in option.recommendation.recommendedDrillIDs {
            if let drill = DrillTemplate.mvpTemplates.first(where: { $0.id == id }) {
                feedbackMessage = "Queued drill: \(drill.title)"
                return
            }
        }
        feedbackMessage = "No mapped drill available for this recommendation."
    }

    private func syncSelectedChord() {
        guard let first = chordChoices.first else {
            selectedChordID = ""
            return
        }

        if !chordChoices.contains(where: { $0.id == selectedChordID }) {
            selectedChordID = first.id
        }
    }
}
