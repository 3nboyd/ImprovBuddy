import SwiftUI
#if os(iOS)
import UIKit
#endif

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
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var services: ServiceContainer
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    @State private var scrollY: CGFloat = 0
    @State private var scrollOriginY: CGFloat?

    private var relatedGridColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 1240 : .infinity
    }

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
        let query = TheoryDisplayFormatter.normalizeForSearch(queryText.trimmingCharacters(in: .whitespacesAndNewlines))
            .lowercased()
        guard !query.isEmpty else { return base }

        return base.filter { chord in
            TheoryDisplayFormatter.normalizeForSearch(chord.name).lowercased().contains(query) ||
            TheoryDisplayFormatter.normalizeForSearch(chord.family).lowercased().contains(query) ||
            chord.symbols.contains(where: { TheoryDisplayFormatter.normalizeForSearch($0).lowercased().contains(query) })
        }
    }

    private var scaleChoices: [TheoryScaleDefinition] {
        let tierRank = selectedTier.rank
        let base = services.theoryKnowledgeBase.scalesByID.values
            .filter { $0.tier.rank <= tierRank }
            .filter { selectedFamilyFilter == "All" || $0.family == selectedFamilyFilter }

        guard !queryText.isEmpty else { return base.sorted { $0.name < $1.name } }
        let query = TheoryDisplayFormatter.normalizeForSearch(queryText.trimmingCharacters(in: .whitespacesAndNewlines))
            .lowercased()
        guard !query.isEmpty else { return base.sorted { $0.name < $1.name } }

        return base.filter { scale in
            TheoryDisplayFormatter.normalizeForSearch(scale.name).lowercased().contains(query) ||
            TheoryDisplayFormatter.normalizeForSearch(scale.family).lowercased().contains(query) ||
            scale.tags.contains(where: { TheoryDisplayFormatter.normalizeForSearch($0).lowercased().contains(query) })
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
        chordChoices.first(where: { $0.id == selectedChordID }) ?? chordChoices.first
    }

    private var scaleAnchor: TheoryScaleDefinition? {
        scaleChoices.first(where: { $0.id == selectedScaleID }) ?? scaleChoices.first
    }

    private var similarityAnchorName: String {
        switch browseMode {
        case .chords:
            TheoryDisplayFormatter.displaySymbol(chordAnchor?.name ?? "-")
        case .scales:
            TheoryDisplayFormatter.displaySymbol(scaleAnchor?.name ?? "-")
        }
    }

    private var effectiveScrollDistance: CGFloat {
        guard let origin = scrollOriginY else { return 0 }
        return max(0, origin - scrollY)
    }

    private var shouldShowTopBlur: Bool {
        effectiveScrollDistance > 10
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: TheoryScrollOffsetPreferenceKey.self,
                            value: proxy.frame(in: .named("theoryLibraryScroll")).minY
                        )
                }
                .frame(height: 0)

                headerSection
                browserSection
            }
            .padding()
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .coordinateSpace(name: "theoryLibraryScroll")
        .navigationTitle("Theory Library")
        .safeAreaInset(edge: .top) {
            keyControlBar
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(shouldShowTopBlur ? .visible : .hidden, for: .navigationBar)
        .onPreferenceChange(TheoryScrollOffsetPreferenceKey.self) { value in
            if scrollOriginY == nil {
                scrollOriginY = value
            }
            scrollY = value
        }
        .onAppear {
            scrollOriginY = nil
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

    private var keyControlBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Browse", selection: $browseMode) {
                    ForEach(TheoryBrowseMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                KeySwipeCarousel(
                    keys: TheoryKey.all.map(\.name),
                    selectedKeyName: $selectedKeyName
                )
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.07))
                .opacity(shouldShowTopBlur ? 1 : 0)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(shouldShowTopBlur ? 0.22 : 0)
        }
        .animation(.easeOut(duration: 0.18), value: shouldShowTopBlur)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                VStack(spacing: 10) {
                    filterMenuCard(
                        title: "Instrument",
                        value: selectedInstrument.displayName
                    ) {
                        ForEach(TheoryInstrumentTransposition.allCases) { mode in
                            Button {
                                selectedInstrument = mode
                            } label: {
                                menuOptionLabel(mode.displayName, selected: selectedInstrument == mode)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    adaptiveFilterPair {
                        filterMenuCard(
                            title: "Clef",
                            value: selectedClef.displayName
                        ) {
                            ForEach(TheoryClef.allCases) { clef in
                                Button {
                                    selectedClef = clef
                                } label: {
                                    menuOptionLabel(clef.displayName, selected: selectedClef == clef)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } right: {
                        filterMenuCard(
                            title: "Tier",
                            value: selectedTier.displayName
                        ) {
                            ForEach(TheoryTier.allCases) { tier in
                                Button {
                                    selectedTier = tier
                                } label: {
                                    menuOptionLabel(tier.displayName, selected: selectedTier == tier)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if browseMode == .chords {
                        adaptiveFilterPair {
                            filterMenuCard(
                                title: "Function",
                                value: selectedFunctionFilter
                            ) {
                                ForEach(functionOptions, id: \.self) { value in
                                    Button {
                                        selectedFunctionFilter = value
                                    } label: {
                                        menuOptionLabel(value, selected: selectedFunctionFilter == value)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        } right: {
                            filterMenuCard(
                                title: "Family",
                                value: selectedFamilyFilter
                            ) {
                                ForEach(familyOptions, id: \.self) { family in
                                    Button {
                                        selectedFamilyFilter = family
                                    } label: {
                                        menuOptionLabel(family, selected: selectedFamilyFilter == family)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        filterMenuCard(
                            title: "Order",
                            value: gridOrder.displayName
                        ) {
                            ForEach(TheoryGridOrder.allCases) { order in
                                Button {
                                    gridOrder = order
                                } label: {
                                    menuOptionLabel(order.displayName, selected: gridOrder == order)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        adaptiveFilterPair {
                            filterMenuCard(
                                title: "Family",
                                value: selectedFamilyFilter
                            ) {
                                ForEach(familyOptions, id: \.self) { family in
                                    Button {
                                        selectedFamilyFilter = family
                                    } label: {
                                        menuOptionLabel(family, selected: selectedFamilyFilter == family)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        } right: {
                            filterMenuCard(
                                title: "Order",
                                value: gridOrder.displayName
                            ) {
                                ForEach(TheoryGridOrder.allCases) { order in
                                    Button {
                                        gridOrder = order
                                    } label: {
                                        menuOptionLabel(order.displayName, selected: gridOrder == order)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
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
            }

            if browseMode == .chords {
                if orderedChords.isEmpty {
                    Text("No chords match the current filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    let mainChord = chordAnchor ?? orderedChords[0]
                    let supportingChords = orderedChords.filter { $0.id != mainChord.id }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Selected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 0) {
                            chordCard(mainChord, isPrimary: true)
                        }

                        if !supportingChords.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("Related Chords")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                if gridOrder == .similarity {
                                    HStack {
                                        Spacer()
                                        Text("Similar to \(similarityAnchorName)")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }

                            LazyVGrid(columns: relatedGridColumns, spacing: 12) {
                                ForEach(supportingChords) { chord in
                                    chordCard(chord)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                if orderedScales.isEmpty {
                    Text("No scales match the current filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    let mainScale = scaleAnchor ?? orderedScales[0]
                    let supportingScales = orderedScales.filter { $0.id != mainScale.id }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Selected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 0) {
                            scaleCard(mainScale)
                        }

                        if !supportingScales.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("Related Scales")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                if gridOrder == .similarity {
                                    HStack {
                                        Spacer()
                                        Text("Similar to \(similarityAnchorName)")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }

                            LazyVGrid(columns: relatedGridColumns, spacing: 12) {
                                ForEach(supportingScales) { scale in
                                    scaleCard(scale)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filterMenuCard<Content: View>(
        title: String,
        value: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(TheoryDisplayFormatter.displaySymbol(value))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func adaptiveFilterPair<Left: View, Right: View>(
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        ViewThatFits {
            HStack(spacing: 10) {
                left()
                right()
            }

            VStack(spacing: 10) {
                left()
                right()
            }
        }
    }

    private func menuOptionLabel(_ label: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(TheoryDisplayFormatter.displaySymbol(label))
            if selected {
                Image(systemName: "checkmark")
            }
        }
    }

    private func chordCard(_ chord: TheoryChordDefinition, isPrimary: Bool = false) -> some View {
        let isSelected = chord.id == selectedChordID
        let showFullPreview = isPrimary || isSelected
        let similarityPct = Int(round(chordSimilarity(chord) * 100))
        let chordNotes = renderedChordNotes(chord)
        let chordPitchClasses = Set(chord.intervals.map { interval in
            Chord.normalizePitchClass(rootPitchClass + interval)
        })
        let chordLabel = compactChordToneLabel(for: chord)
        let option = showFullPreview
            ? services.theoryResolver.options(
                forChordID: chord.id,
                context: context,
                functionFilter: functionFilter,
                sortMode: .relevance
            ).first
            : nil

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TheoryDisplayFormatter.displaySymbol(chord.name))
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

            if showFullPreview, let option {
                Text("Best: \(TheoryDisplayFormatter.displaySymbol(option.primaryScale.name))")
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
                PianoStripView(
                    highlightedPitchClasses: Set(primaryNotes.map(\.spelled.pitchClass)),
                    displayNamesByPitchClass: pitchClassLabelMap(from: primaryNotes)
                )

                ViewThatFits {
                    HStack {
                        Button("Play Chord") {
                            synth.playChordMIDINotes(chordNotes.map(\.spelled.midi))
                        }
                        .buttonStyle(.bordered)

                        if let firstArp = option.arpeggios.first {
                            Button("Play Arpeggio") {
                                let arpNotes = services.theoryResolver.renderedArpeggioNotes(
                                    arpeggio: firstArp,
                                    rootPitchClass: rootPitchClass,
                                    context: context
                                )
                                synth.playMIDINotes(arpNotes.map(\.spelled.midi))
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    VStack(alignment: .leading) {
                        Button("Play Chord") {
                            synth.playChordMIDINotes(chordNotes.map(\.spelled.midi))
                        }
                        .buttonStyle(.bordered)

                        if let firstArp = option.arpeggios.first {
                            Button("Play Arpeggio") {
                                let arpNotes = services.theoryResolver.renderedArpeggioNotes(
                                    arpeggio: firstArp,
                                    rootPitchClass: rootPitchClass,
                                    context: context
                                )
                                synth.playMIDINotes(arpNotes.map(\.spelled.midi))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if !option.alternatives.isEmpty {
                    Text("Alternatives: \(option.alternatives.map { TheoryDisplayFormatter.displaySymbol($0.name) }.joined(separator: ", "))")
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
                .stroke(isSelected ? appEnvironment.accentColor : Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedChordID = chord.id
            }
        }
    }

    private func compactChordToneLabel(for chord: TheoryChordDefinition) -> String {
        chord.intervals
            .map { interval in
                let pitchClass = Chord.normalizePitchClass(rootPitchClass + interval)
                return TheoryDisplayFormatter.displaySymbol(Chord.pitchClassNames[pitchClass])
            }
            .joined(separator: " ")
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
                    Text(TheoryDisplayFormatter.displaySymbol(scale.name))
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
                PianoStripView(
                    highlightedPitchClasses: pitchClasses,
                    displayNamesByPitchClass: pitchClassLabelMap(from: notes)
                )

                Button("Play Scale") {
                    synth.playMIDINotes(notes.map(\.spelled.midi))
                }
                .buttonStyle(.bordered)

                if !relatedChords.isEmpty {
                    Text("Common over: \(relatedChords.map(TheoryDisplayFormatter.displaySymbol).joined(separator: ", "))")
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
                .stroke(isSelected ? appEnvironment.accentColor : Color.white.opacity(0.08), lineWidth: 1)
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
            .background(appEnvironment.accentColor.opacity(0.2), in: Capsule())
            .foregroundStyle(appEnvironment.accentColor)
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
        notes.map { TheoryDisplayFormatter.displaySymbol($0.spelled.name) }.joined(separator: " ")
    }

    private func pitchClassLabelMap(from notes: [StaffRenderedNote]) -> [Int: String] {
        var map: [Int: String] = [:]
        for note in notes {
            if map[note.spelled.pitchClass] == nil {
                map[note.spelled.pitchClass] = note.spelled.name
            }
        }
        return map
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

private struct KeySwipeCarousel: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment

    let keys: [String]
    @Binding var selectedKeyName: String

    @State private var isSliding = false
    @State private var anchorIndex = 0
    @State private var showSwipeHint = false
    @State private var hideSwipeHintWorkItem: DispatchWorkItem?
#if os(iOS)
    private let feedback = UISelectionFeedbackGenerator()
#endif

    var body: some View {
        Group {
            if keys.isEmpty {
                EmptyView()
            } else {
                let index = currentIndex
                let previous = keys[(index - 1 + keys.count) % keys.count]
                let next = keys[(index + 1) % keys.count]

                ZStack {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    appEnvironment.accentColor.opacity(isSliding ? 0.40 : 0.32),
                                    appEnvironment.accentColor.opacity(isSliding ? 0.30 : 0.22)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Capsule()
                        .stroke(appEnvironment.accentColor.opacity(isSliding ? 0.78 : 0.62), lineWidth: 1.1)

                    VStack(spacing: 1) {
                        Text(TheoryDisplayFormatter.displaySymbol(previous))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appEnvironment.accentColor.opacity(0.88))
                            .opacity(0.86)

                        Text(TheoryDisplayFormatter.displaySymbol(selectedKeyName))
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(appEnvironment.accentColor)
                            .shadow(color: appEnvironment.accentColor.opacity(0.38), radius: 2, x: 0, y: 0)
                            .lineLimit(1)

                        Text(TheoryDisplayFormatter.displaySymbol(next))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appEnvironment.accentColor.opacity(0.88))
                            .opacity(0.86)
                    }
                    .frame(width: 58, height: 60)
                    .overlay(alignment: .trailing) {
                        if showSwipeHint && !isSliding {
                            VStack(spacing: 1) {
                                Image(systemName: "chevron.up")
                                Image(systemName: "chevron.down")
                            }
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(appEnvironment.accentColor.opacity(0.92))
                            .padding(.trailing, 5)
                            .transition(.opacity)
                        }
                    }
                    .mask(
                        RoundedRectangle(cornerRadius: 14)
                            .padding(.vertical, -5)
                    )
                }
                .frame(width: 78, height: 66)
                .animation(.easeInOut(duration: 0.15), value: selectedKeyName)
                .gesture(scrubGesture)
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            showSwipeDirectionHint()
                        }
                )
                .accessibilityLabel("Key Carousel")
            }
        }
    }

    private var currentIndex: Int {
        if let found = keys.firstIndex(of: selectedKeyName) {
            return found
        }
        return 0
    }

    private var scrubGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.16)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    beginSlidingIfNeeded()
                case let .second(true, drag?):
                    beginSlidingIfNeeded()
                    updateSelection(with: drag.translation.height)
                default:
                    break
                }
            }
            .onEnded { _ in
                isSliding = false
            }
    }

    private func beginSlidingIfNeeded() {
        guard !isSliding else { return }
        hideSwipeHintWorkItem?.cancel()
        withAnimation(.easeOut(duration: 0.1)) {
            showSwipeHint = false
        }
        anchorIndex = currentIndex
        isSliding = true
#if os(iOS)
        feedback.prepare()
#endif
    }

    private func updateSelection(with translationY: CGFloat) {
        guard isSliding, !keys.isEmpty else { return }
        let stepDelta = Int((-translationY / 18).rounded(.toNearestOrAwayFromZero))
        var targetIndex = anchorIndex + stepDelta
        while targetIndex < 0 { targetIndex += keys.count }
        targetIndex %= keys.count

        let nextKey = keys[targetIndex]
        guard nextKey != selectedKeyName else { return }
        selectedKeyName = nextKey
        emitHapticTick()
    }

    private func emitHapticTick() {
#if os(iOS)
        feedback.selectionChanged()
        feedback.prepare()
#endif
    }

    private func showSwipeDirectionHint() {
        hideSwipeHintWorkItem?.cancel()
        withAnimation(.easeOut(duration: 0.14)) {
            showSwipeHint = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.2)) {
                showSwipeHint = false
            }
        }
        hideSwipeHintWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }
}

private struct TheoryScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct MiniPitchClassStrip: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment

    let highlightedPitchClasses: Set<Int>

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { pitchClass in
                RoundedRectangle(cornerRadius: 2)
                    .fill(highlightedPitchClasses.contains(pitchClass) ? appEnvironment.accentColor : Color.white.opacity(0.14))
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
