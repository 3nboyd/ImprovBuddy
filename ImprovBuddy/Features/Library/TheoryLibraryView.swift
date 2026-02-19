import SwiftUI

private enum TheoryBrowseMode: String, CaseIterable, Identifiable {
    case chords
    case scales

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chords: "Chords"
        case .scales: "Scales"
        }
    }
}

private enum TheoryGridOrder: String, CaseIterable, Identifiable {
    case similarity
    case alphabetical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .similarity: "Similarity"
        case .alphabetical: "A-Z"
        }
    }
}

struct TheoryLibraryView: View {
    @EnvironmentObject private var services: ServiceContainer
    @StateObject private var synth = SimpleSynth()

    @State private var browseMode: TheoryBrowseMode = .chords
    @State private var selectedChordID = ""
    @State private var selectedScaleID = ""

    @State private var selectedKeyName = TheoryKey.defaultKey.name
    @State private var selectedInstrument: TheoryInstrumentTransposition = .concert
    @State private var selectedClef: TheoryClef = .treble
    @State private var selectedTier: TheoryTier = .core

    @State private var selectedFunctionFilter = "All"
    @State private var selectedFamilyFilter = "All"
    @State private var gridOrder: TheoryGridOrder = .similarity
    @State private var queryText = ""
    @State private var showAdvancedFilters = false

    @State private var feedbackMessage = ""

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var functionOptions: [String] {
        ["All"] + TheoryFunctionTag.allCases.map(\.displayName)
    }

    private var scaleFamilyOptions: [String] {
        let families = Set(services.theoryKnowledgeBase.scalesByID.values.map(\.family))
        return ["All"] + families.sorted()
    }

    private var chordFamilyOptions: [String] {
        services.theoryResolver.availableFamilies()
    }

    private var familyOptions: [String] {
        browseMode == .chords ? chordFamilyOptions : scaleFamilyOptions
    }

    private var functionFilter: TheoryFunctionTag? {
        TheoryFunctionTag.allCases.first(where: { $0.displayName == selectedFunctionFilter })
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

    private var rootPitchClass: Int {
        TheoryKey.byName(selectedKeyName).rootPitchClass
    }

    private var chordChoices: [TheoryChordDefinition] {
        let base = services.theoryResolver.availableChordDefinitions(
            tier: selectedTier,
            functionFilter: functionFilter,
            familyFilter: selectedFamilyFilter
        )

        guard !queryText.isEmpty else { return base }
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }

        return base.filter { chord in
            chord.name.lowercased().contains(query) ||
            chord.family.lowercased().contains(query) ||
            chord.symbols.contains(where: { $0.lowercased().contains(query) })
        }
    }

    private var scaleChoices: [TheoryScaleDefinition] {
        let tierRank = selectedTier.rank
        let base = services.theoryKnowledgeBase.scalesByID.values
            .filter { $0.tier.rank <= tierRank }
            .filter { selectedFamilyFilter == "All" || $0.family == selectedFamilyFilter }

        guard !queryText.isEmpty else { return base.sorted { $0.name < $1.name } }
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base.sorted { $0.name < $1.name } }

        return base.filter { scale in
            scale.name.lowercased().contains(query) ||
            scale.family.lowercased().contains(query) ||
            scale.tags.contains(where: { $0.lowercased().contains(query) })
        }
        .sorted { $0.name < $1.name }
    }

    private var orderedChords: [TheoryChordDefinition] {
        let base = chordChoices
        guard gridOrder == .similarity else {
            return base.sorted { $0.name < $1.name }
        }

        guard let anchor = chordAnchor else { return base }
        return base.sorted { lhs, rhs in
            let l = similarity(lhs.intervals, anchor.intervals)
            let r = similarity(rhs.intervals, anchor.intervals)
            if l != r { return l > r }
            return lhs.name < rhs.name
        }
    }

    private var orderedScales: [TheoryScaleDefinition] {
        let base = scaleChoices
        guard gridOrder == .similarity else {
            return base.sorted { $0.name < $1.name }
        }

        guard let anchor = scaleAnchor else { return base }
        return base.sorted { lhs, rhs in
            let l = similarity(lhs.intervals, anchor.intervals)
            let r = similarity(rhs.intervals, anchor.intervals)
            if l != r { return l > r }
            return lhs.name < rhs.name
        }
    }

    private var chordAnchor: TheoryChordDefinition? {
        orderedChords.first(where: { $0.id == selectedChordID }) ?? orderedChords.first
    }

    private var scaleAnchor: TheoryScaleDefinition? {
        orderedScales.first(where: { $0.id == selectedScaleID }) ?? orderedScales.first
    }

    private var similarityAnchorName: String {
        switch browseMode {
        case .chords:
            chordAnchor?.name ?? "-"
        case .scales:
            scaleAnchor?.name ?? "-"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                browserSection

                if !feedbackMessage.isEmpty {
                    Text(feedbackMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Theory Library")
        .onAppear {
            sanitizeFiltersForMode()
            syncSelection()
        }
        .onChange(of: browseMode) { _, _ in
            sanitizeFiltersForMode()
            syncSelection()
        }
        .onChange(of: selectedTier) { _, _ in syncSelection() }
        .onChange(of: selectedFunctionFilter) { _, _ in syncSelection() }
        .onChange(of: selectedFamilyFilter) { _, _ in syncSelection() }
        .onChange(of: queryText) { _, _ in syncSelection() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("Browse", selection: $browseMode) {
                    ForEach(TheoryBrowseMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Key", selection: $selectedKeyName) {
                    ForEach(TheoryKey.all, id: \.name) { key in
                        Text(key.name).tag(key.name)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    browseMode == .chords ? "Search chords or symbols" : "Search scales or families",
                    text: $queryText
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            DisclosureGroup(isExpanded: $showAdvancedFilters) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Picker("Instrument", selection: $selectedInstrument) {
                            ForEach(TheoryInstrumentTransposition.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Clef", selection: $selectedClef) {
                            ForEach(TheoryClef.allCases) { clef in
                                Text(clef.displayName).tag(clef)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Tier", selection: $selectedTier) {
                            ForEach(TheoryTier.allCases) { tier in
                                Text(tier.displayName).tag(tier)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack(spacing: 10) {
                        if browseMode == .chords {
                            Picker("Function", selection: $selectedFunctionFilter) {
                                ForEach(functionOptions, id: \.self) { value in
                                    Text(value).tag(value)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Picker("Family", selection: $selectedFamilyFilter) {
                            ForEach(familyOptions, id: \.self) { family in
                                Text(family).tag(family)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Order", selection: $gridOrder) {
                            ForEach(TheoryGridOrder.allCases) { order in
                                Text(order.displayName).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Advanced Filters", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var browserSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(browseMode == .chords ? "Chord Browser" : "Scale Browser")
                    .font(.headline)

                Spacer()

                if gridOrder == .similarity {
                    Text("Similar to \(similarityAnchorName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if browseMode == .chords {
                if orderedChords.isEmpty {
                    Text("No chords match the current filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(orderedChords) { chord in
                            chordCard(chord)
                        }
                    }
                }
            } else {
                if orderedScales.isEmpty {
                    Text("No scales match the current filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(orderedScales) { scale in
                            scaleCard(scale)
                        }
                    }
                }
            }
        }
    }

    private func chordCard(_ chord: TheoryChordDefinition) -> some View {
        let isSelected = chord.id == selectedChordID
        let similarityPct = Int(round(chordSimilarity(chord) * 100))
        let chordNotes = renderedChordNotes(chord)
        let chordLabel = compactNoteLabel(from: chordNotes)
        let chordPitchClasses = Set(chordNotes.map(\.spelled.pitchClass))
        let option = services.theoryResolver.options(
            forChordID: chord.id,
            context: context,
            functionFilter: functionFilter,
            sortMode: .relevance
        ).first

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chord.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(chord.family)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if gridOrder == .similarity {
                    similarityBadge(similarityPct)
                }
            }

            Text(chordLabel)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            MiniPitchClassStrip(highlightedPitchClasses: chordPitchClasses)

            if let option {
                Text("Best: \(option.primaryScale.name)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if isSelected, let option {
                Divider().padding(.vertical, 2)

                Text(option.recommendation.rationale)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                let primaryNotes = services.theoryResolver.renderedScaleNotes(
                    scale: option.primaryScale,
                    rootPitchClass: rootPitchClass,
                    context: context
                )

                StaffView(notes: primaryNotes, clef: selectedClef)
                PianoStripView(highlightedPitchClasses: Set(primaryNotes.map(\.spelled.pitchClass)))

                ViewThatFits {
                    HStack {
                        Button("Audition") {
                            synth.playMIDINotes(primaryNotes.map(\.spelled.midi))
                        }
                        .buttonStyle(.bordered)

                        if let firstArp = option.arpeggios.first {
                            Button("Arp") {
                                let arpNotes = services.theoryResolver.renderedArpeggioNotes(
                                    arpeggio: firstArp,
                                    rootPitchClass: rootPitchClass,
                                    context: context
                                )
                                synth.playMIDINotes(arpNotes.map(\.spelled.midi))
                            }
                            .buttonStyle(.bordered)
                        }

                        Button("Send") {
                            queueDrill(from: option)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    VStack(alignment: .leading) {
                        Button("Audition") {
                            synth.playMIDINotes(primaryNotes.map(\.spelled.midi))
                        }
                        .buttonStyle(.bordered)

                        if let firstArp = option.arpeggios.first {
                            Button("Arpeggio") {
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

                if !option.alternatives.isEmpty {
                    Text("Alternatives: \(option.alternatives.map(\.name).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedChordID = chord.id
            }
        }
    }

    private func scaleCard(_ scale: TheoryScaleDefinition) -> some View {
        let isSelected = scale.id == selectedScaleID
        let similarityPct = Int(round(scaleSimilarity(scale) * 100))
        let notes = services.theoryResolver.renderedScaleNotes(
            scale: scale,
            rootPitchClass: rootPitchClass,
            context: context
        )
        let noteLabel = compactNoteLabel(from: notes)
        let pitchClasses = Set(notes.map(\.spelled.pitchClass))
        let relatedChords = relatedChordNames(for: scale)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scale.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(scale.family)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if gridOrder == .similarity {
                    similarityBadge(similarityPct)
                }
            }

            Text(noteLabel)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            MiniPitchClassStrip(highlightedPitchClasses: pitchClasses)

            Text(scale.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(isSelected ? 4 : 2)

            if isSelected {
                Divider().padding(.vertical, 2)

                StaffView(notes: notes, clef: selectedClef)
                PianoStripView(highlightedPitchClasses: pitchClasses)

                Button("Audition Scale") {
                    synth.playMIDINotes(notes.map(\.spelled.midi))
                }
                .buttonStyle(.bordered)

                if !relatedChords.isEmpty {
                    Text("Common over: \(relatedChords.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedScaleID = scale.id
            }
        }
    }

    private func similarityBadge(_ percentage: Int) -> some View {
        Text("\(percentage)%")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.2), in: Capsule())
            .foregroundStyle(Color.accentColor)
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

    private func sanitizeFiltersForMode() {
        if !familyOptions.contains(selectedFamilyFilter) {
            selectedFamilyFilter = "All"
        }

        if browseMode == .scales {
            selectedFunctionFilter = "All"
        }
    }

    private func syncSelection() {
        sanitizeFiltersForMode()

        if browseMode == .chords {
            guard let first = orderedChords.first else {
                selectedChordID = ""
                return
            }

            if !orderedChords.contains(where: { $0.id == selectedChordID }) {
                selectedChordID = first.id
            }
            return
        }

        guard let first = orderedScales.first else {
            selectedScaleID = ""
            return
        }

        if !orderedScales.contains(where: { $0.id == selectedScaleID }) {
            selectedScaleID = first.id
        }
    }

    private func compactNoteLabel(from notes: [StaffRenderedNote]) -> String {
        notes.map { $0.spelled.name }.joined(separator: " ")
    }

    private func renderedChordNotes(_ chord: TheoryChordDefinition) -> [StaffRenderedNote] {
        let spelled = services.theoryResolver.notationEngine.spellIntervals(
            intervals: chord.intervals,
            degreeSteps: chord.degreeSteps,
            context: context,
            rootPitchClass: rootPitchClass
        )
        return services.theoryResolver.notationEngine.toStaffNotes(spelled, clef: selectedClef)
    }

    private func relatedChordNames(for scale: TheoryScaleDefinition) -> [String] {
        let recommendations = services.theoryKnowledgeBase.envelope.dataset.recommendations.filter { recommendation in
            recommendation.primaryScaleID == scale.id || recommendation.alternativeScaleIDs.contains(scale.id)
        }

        let names = recommendations.compactMap { services.theoryKnowledgeBase.chordsByID[$0.chordID]?.name }
        return Array(Set(names)).sorted()
    }

    private func chordSimilarity(_ chord: TheoryChordDefinition) -> Double {
        guard let anchor = chordAnchor else { return 0 }
        return similarity(chord.intervals, anchor.intervals)
    }

    private func scaleSimilarity(_ scale: TheoryScaleDefinition) -> Double {
        guard let anchor = scaleAnchor else { return 0 }
        return similarity(scale.intervals, anchor.intervals)
    }

    private func similarity(_ lhs: [Int], _ rhs: [Int]) -> Double {
        let a = Set(lhs.map(Chord.normalizePitchClass))
        let b = Set(rhs.map(Chord.normalizePitchClass))
        let union = a.union(b)
        guard !union.isEmpty else { return 1 }
        let intersection = a.intersection(b)
        return Double(intersection.count) / Double(union.count)
    }
}

private struct MiniPitchClassStrip: View {
    let highlightedPitchClasses: Set<Int>

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { pitchClass in
                RoundedRectangle(cornerRadius: 2)
                    .fill(highlightedPitchClasses.contains(pitchClass) ? Color.accentColor : Color.white.opacity(0.14))
                    .frame(height: 6)
            }
        }
    }
}

private extension TheoryTier {
    var rank: Int {
        switch self {
        case .core: 0
        case .extended: 1
        case .advanced: 2
        }
    }
}
