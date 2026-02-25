import SwiftUI

struct ToolsHomeView: View {
    var body: some View {
        NavigationStack {
            ToolsStudioView()
        }
    }
}

struct ToolsStudioView: View {
    @EnvironmentObject private var services: ServiceContainer

    @StateObject private var tunerPreviewSynth = SimpleSynth()

    @State private var showTunerSettings = false
    @State private var showMetronomeSettings = false
    @State private var didBootstrapInputs = false
    @State private var displayedBPM = MetronomeSettings.default.bpm
    @State private var beatFlash = false
    @State private var lastHapticStep = Int(round(MetronomeSettings.default.bpm))
    @State private var lastAudibleVolume = MetronomeSettings.default.masterVolume
    @State private var activeDropUp: BottomDropUpMenu?
    @State private var bpmEntryText = ""
    @State private var tunerHeldMIDINote: Int?
    @State private var tunerSustainedMIDINote: Int?
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var isBPMFieldFocused: Bool

    @State private var micLease: AudioUsageCoordinator.LeaseToken?
    @State private var midiLease: AudioUsageCoordinator.LeaseToken?
    private let bottomControlPopupClearance: CGFloat = 98
    private let bpmFeedback = UIImpactFeedbackGenerator(style: .rigid)
    private let sustainFeedback = UIImpactFeedbackGenerator(style: .soft)
    private let meterPresets: [MeterSignature] = [
        MeterSignature(top: 2, bottom: 4),
        MeterSignature(top: 3, bottom: 4),
        MeterSignature(top: 4, bottom: 4),
        MeterSignature(top: 5, bottom: 4),
        MeterSignature(top: 6, bottom: 8),
        MeterSignature(top: 7, bottom: 8),
        MeterSignature(top: 9, bottom: 8),
        MeterSignature(top: 12, bottom: 8)
    ]
    private var beatsPerBar: Int { max(1, services.metronomeEngine.meter.top) }
    private var stepsPerBeat: Int { max(1, services.metronomeEngine.subdivision.rawValue) }
    private var totalStepsPerBar: Int { beatsPerBar * stepsPerBeat }
    private var visualStepInBar: Int {
        guard totalStepsPerBar > 0 else { return 0 }
        if services.metronomeEngine.isRunning {
            return max(0, services.metronomeEngine.currentStep - 1) % totalStepsPerBar
        }
        return 0
    }
    private var countInBeatsPerRow: Int { max(1, services.metronomeEngine.meter.top) }
    private var countInTotalBeats: Int { max(0, services.metronomeEngine.countInBars * countInBeatsPerRow) }
    private var countInCompletedBeats: Int {
        guard countInTotalBeats > 0 else { return 0 }
        let stepsPerBeat = max(1, services.metronomeEngine.subdivision.rawValue)
        let completed = (max(0, services.metronomeEngine.currentStep) + stepsPerBeat - 1) / stepsPerBeat
        return min(countInTotalBeats, completed)
    }
    private var shouldShowCountInOverlay: Bool {
        services.metronomeEngine.isCountInActive && countInTotalBeats > 0
    }
    private var contentLiftOffset: CGFloat {
        guard isBPMFieldFocused else { return 0 }
        let dynamicLift = max(138, min(232, keyboardHeight * 0.56))
        return -dynamicLift
    }

    private var tunerSettingsBinding: Binding<TunerSettings> {
        Binding(
            get: { services.toolsSettings.tuner },
            set: { services.toolsSettings.tuner = $0 }
        )
    }

    private var metronomeSettingsBinding: Binding<MetronomeSettings> {
        Binding(
            get: { services.toolsSettings.metronome },
            set: { services.toolsSettings.metronome = $0 }
        )
    }

    private var tunerStatusText: String {
        if let error = services.audioUsageCoordinator.lastErrorMessage, !error.isEmpty {
            return error
        }
        if !services.audioManager.micPermissionGranted {
            return "Microphone permission required for audio pitch tracking."
        }
        if services.audioManager.isRunning {
            return "Listening on \(services.audioManager.currentRouteName)"
        }
        return "No input route"
    }

    var body: some View {
        ZStack {
            if activeDropUp != nil {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.16)) {
                            activeDropUp = nil
                        }
                    }
            }

            VStack(spacing: 12) {
                Spacer(minLength: 0)
                studioSurface
                bottomControlRow
            }
            .offset(y: contentLiftOffset)
            .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isBPMFieldFocused)

            VStack {
                HStack {
                    Spacer()
                    topTrailingToolsRail
                }
                Spacer()
            }

            if shouldShowCountInOverlay {
                CountInDotsOverlay(
                    beatsPerRow: countInBeatsPerRow,
                    totalBeats: countInTotalBeats,
                    completedBeats: countInCompletedBeats
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeOut(duration: 0.15), value: countInCompletedBeats)
                .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .sheet(isPresented: $showTunerSettings) {
            TunerSettingsSheet(settings: tunerSettingsBinding) {
                services.toolsSettings.resetTuner()
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showMetronomeSettings) {
            MetronomeSettingsSheet(settings: metronomeSettingsBinding) {
                services.toolsSettings.resetMetronome()
            }
            .presentationDetents([.medium, .large])
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    commitBPMEntry()
                    isBPMFieldFocused = false
                }
            }
        }
        .task {
            await bootstrapInputsIfNeeded()
        }
        .onAppear {
            displayedBPM = services.metronomeEngine.bpm
            bpmEntryText = "\(Int(round(displayedBPM)))"
            lastHapticStep = Int(round(displayedBPM))
            lastAudibleVolume = max(0.05, services.metronomeEngine.masterVolume)
            bpmFeedback.prepare()
            sustainFeedback.prepare()
        }
        .onChange(of: services.metronomeEngine.bpm) { _, newValue in
            displayedBPM = newValue
            if !isBPMFieldFocused {
                bpmEntryText = "\(Int(round(newValue)))"
            }
        }
        .onChange(of: isBPMFieldFocused) { _, focused in
            if !focused {
                commitBPMEntry()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard
                let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else {
                return
            }
            keyboardHeight = max(0, frame.height)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onChange(of: services.metronomeEngine.beatPulseID) { _, _ in
            guard services.metronomeEngine.isRunning else { return }
            withAnimation(.easeOut(duration: 0.1)) {
                beatFlash = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                withAnimation(.easeIn(duration: 0.22)) {
                    beatFlash = false
                }
            }
        }
        .onDisappear {
            services.liveTempoAnalyzer.stop()
            services.audioUsageCoordinator.release(micLease)
            services.audioUsageCoordinator.release(midiLease)
            tunerPreviewSynth.stopSustainedMIDINote()
            micLease = nil
            midiLease = nil
            didBootstrapInputs = false
            activeDropUp = nil
            tunerHeldMIDINote = nil
            tunerSustainedMIDINote = nil
        }
    }

    private var studioSurface: some View {
        VStack(spacing: 14) {
            tunerSection
                .frame(minHeight: 194)
            metronomeSection
        }
    }

    private var tunerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tuner")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .center, spacing: 16) {
                PitchAccuracyRing(
                    cents: services.tunerEngine.cents,
                    confidence: services.tunerEngine.confidence,
                    detectedMIDINote: services.tunerEngine.midiNote,
                    isSustainActive: tunerSustainedMIDINote != nil,
                    onHoldStart: { note in
                        beginTunerPreviewHold(note: note)
                    },
                    onHoldEnd: {
                        endTunerPreviewHold()
                    },
                    onSustainSwipeUp: { note in
                        latchTunerSustain(note: note)
                    },
                    onToggleSustain: {
                        toggleTunerSustain()
                    }
                )
                .frame(width: 144, height: 144)

                VStack(alignment: .leading, spacing: 4) {
                    Text(services.tunerEngine.noteName)
                        .font(.system(size: 80, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)

                    Text(String(format: "%+.1f cents", services.tunerEngine.cents))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(centsColor(services.tunerEngine.cents))

                    Text(tunerStatusText)
                        .font(.caption)
                        .foregroundStyle(services.tunerEngine.isStable ? .green : .secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var topTrailingToolsRail: some View {
        VStack(spacing: 10) {
            Button {
                showTunerSettings = true
            } label: {
                Image(systemName: "tuningfork")
                    .font(.body.weight(.bold))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tuner Settings")

            VerticalVolumeRail(
                volume: services.metronomeEngine.masterVolume,
                onVolumeAdjust: { value in
                    applyVolume(value)
                }
            )
        }
        .padding(.top, 4)
    }

    private var metronomeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Metronome")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .opacity(beatFlash && services.metronomeEngine.isRunning ? 1 : 0.18)
                    .scaleEffect(beatFlash && services.metronomeEngine.isRunning ? 1.32 : 1)
                    .animation(.easeOut(duration: 0.1), value: beatFlash)

                if let error = services.metronomeEngine.lastErrorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if services.metronomeEngine.isCountInActive {
                    Text("Count-In")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showMetronomeSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.footnote.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Metronome Settings")
            }

            metronomeVisualCounter

            PrecisionTempoSlider(
                value: displayedBPM,
                isRunning: services.metronomeEngine.isRunning,
                beatFlash: beatFlash,
                onValueChanged: { value in
                    handleBPMChange(value)
                }
            )
            .frame(height: 62)

            HStack(spacing: 12) {
                DropUpActionButton(
                    icon: "hand.tap.fill",
                    title: "Tap Tempo"
                ) {
                    activeDropUp = nil
                    if let tappedBPM = services.metronomeEngine.registerTapTempo() {
                        handleBPMChange(tappedBPM)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    TextField("BPM", text: $bpmEntryText)
                        .focused($isBPMFieldFocused)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .onTapGesture {
                            isBPMFieldFocused = true
                        }
                    Text("BPM")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 88)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isBPMFieldFocused ? Color.accentColor.opacity(0.85) : Color.accentColor.opacity(0.36), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    isBPMFieldFocused = true
                }
                .frame(maxWidth: .infinity)

                Button(action: toggleMetronome) {
                    VStack(spacing: 0) {
                        Image(systemName: services.metronomeEngine.isRunning ? "stop.fill" : "play.fill")
                            .font(.title2.weight(.bold))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.65), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(services.metronomeEngine.isRunning ? "Stop Metronome" : "Start Metronome")
            }
        }
    }

    private var metronomeVisualCounter: some View {
        let currentBeat = visualStepInBar / stepsPerBeat
        let currentSubStep = visualStepInBar % stepsPerBeat

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pulse \(services.metronomeEngine.meter.displayName) • \(services.metronomeEngine.subdivision.notationSymbol)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Beat \(min(beatsPerBar, currentBeat + 1))/\(beatsPerBar)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(0..<beatsPerBar, id: \.self) { beatIndex in
                    beatProgressTile(
                        beatIndex: beatIndex,
                        currentBeat: currentBeat,
                        currentSubStep: currentSubStep
                    )
                }
            }
        }
    }

    private func beatProgressTile(
        beatIndex: Int,
        currentBeat: Int,
        currentSubStep: Int
    ) -> some View {
        let isRunning = services.metronomeEngine.isRunning
        let isPastBeat = beatIndex < currentBeat
        let isCurrentBeat = isRunning && beatIndex == currentBeat
        let completedSubsteps: Int

        if isPastBeat {
            completedSubsteps = stepsPerBeat
        } else if isCurrentBeat {
            completedSubsteps = min(stepsPerBeat, currentSubStep + 1)
        } else {
            completedSubsteps = 0
        }

        return HStack(spacing: 2) {
            ForEach(0..<stepsPerBeat, id: \.self) { subdivisionStep in
                Rectangle()
                    .fill(
                        subdivisionStep < completedSubsteps
                            ? Color.accentColor.opacity(isCurrentBeat ? 0.98 : 0.84)
                            : Color.accentColor.opacity(0.16)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(isCurrentBeat ? 0.2 : 0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(isCurrentBeat ? 0.82 : 0.3), lineWidth: 1)
        )
        .scaleEffect(beatFlash && isCurrentBeat ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: beatFlash)
    }

    private var bottomControlRow: some View {
        HStack(spacing: 10) {
            BottomSquareControlButton(
                icon: "music.quarternote.3",
                title: "Meter",
                detail: services.metronomeEngine.meter.displayName,
                isActive: activeDropUp == .meter
            ) {
                toggleDropUp(.meter)
            }
            .overlay(alignment: .bottom) {
                if activeDropUp == .meter {
                    columnOverlayMenu(for: .meter)
                        .offset(y: -bottomControlPopupClearance)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .zIndex(activeDropUp == .meter ? 20 : 0)

            BottomSquareControlButton(
                icon: "music.note",
                title: "Subdivision",
                detail: services.metronomeEngine.subdivision.notationSymbol,
                symbolOnlyDetail: true,
                isActive: activeDropUp == .subdivision
            ) {
                toggleDropUp(.subdivision)
            }
            .overlay(alignment: .bottom) {
                if activeDropUp == .subdivision {
                    columnOverlayMenu(for: .subdivision)
                        .offset(y: -bottomControlPopupClearance)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .zIndex(activeDropUp == .subdivision ? 20 : 0)

            BottomSquareControlButton(
                icon: "music.note.list",
                title: "Sound",
                detail: services.metronomeEngine.soundSet.displayName,
                isActive: activeDropUp == .sound
            ) {
                toggleDropUp(.sound)
            }
            .overlay(alignment: .bottom) {
                if activeDropUp == .sound {
                    columnOverlayMenu(for: .sound)
                        .offset(y: -bottomControlPopupClearance)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .zIndex(activeDropUp == .sound ? 20 : 0)

            BottomSquareControlButton(
                icon: "countdown",
                title: "Count-In",
                detail: "\(services.metronomeEngine.countInBars)",
                isActive: activeDropUp == .countIn
            ) {
                toggleDropUp(.countIn)
            }
            .overlay(alignment: .bottom) {
                if activeDropUp == .countIn {
                    columnOverlayMenu(for: .countIn)
                        .offset(y: -bottomControlPopupClearance)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .zIndex(activeDropUp == .countIn ? 20 : 0)
        }
    }

    @ViewBuilder
    private func columnOverlayMenu(for kind: BottomDropUpMenu) -> some View {
        VStack(spacing: 6) {
            switch kind {
            case .meter:
                ForEach(meterPresets, id: \.displayName) { meter in
                    overlayOptionButton(
                        label: meter.displayName,
                        selected: meter == services.metronomeEngine.meter
                    ) {
                        updateMetronomeSettings { settings in
                            settings.meter = meter
                        }
                    }
                }
            case .subdivision:
                ForEach(MetronomeSubdivision.allCases) { option in
                    overlayOptionButton(
                        label: option.notationSymbol,
                        selected: option == services.metronomeEngine.subdivision,
                        largeSymbol: true
                    ) {
                        updateMetronomeSettings { settings in
                            settings.subdivision = option
                        }
                    }
                }
            case .countIn:
                ForEach(0...4, id: \.self) { bars in
                    overlayOptionButton(
                        label: "\(bars) bars",
                        selected: bars == services.metronomeEngine.countInBars
                    ) {
                        updateMetronomeSettings { settings in
                            settings.countInBars = bars
                        }
                    }
                }
            case .sound:
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6)
                    ],
                    spacing: 6
                ) {
                    ForEach(MetronomeSoundSet.allCases) { soundSet in
                        overlayOptionButton(
                            label: soundSet.displayName,
                            selected: soundSet == services.metronomeEngine.soundSet,
                            compact: true
                        ) {
                            updateMetronomeSettings { settings in
                                settings.soundSet = soundSet
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(width: kind == .sound ? 300 : 118)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func overlayOptionButton(
        label: String,
        selected: Bool,
        largeSymbol: Bool = false,
        compact: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            withAnimation(.easeOut(duration: 0.16)) {
                activeDropUp = nil
            }
        } label: {
            Text(label)
                .font(
                    largeSymbol
                        ? .title3.weight(.semibold)
                        : (compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, largeSymbol ? 10 : (compact ? 6 : 8))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.9) : Color.accentColor.opacity(0.16))
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleDropUp(_ menu: BottomDropUpMenu) {
        withAnimation(.easeOut(duration: 0.16)) {
            activeDropUp = activeDropUp == menu ? nil : menu
        }
    }

    private func toggleMetronome() {
        if services.metronomeEngine.isRunning {
            services.metronomeEngine.stop()
        } else {
            services.metronomeEngine.start()
        }
    }

    private func handleBPMChange(_ value: Double) {
        let clamped = max(30, min(320, value))
        displayedBPM = clamped
        services.metronomeEngine.setBPM(clamped)
        services.liveTempoAnalyzer.targetBPM = clamped
        syncMetronomeBPMToSettings(from: clamped)

        let rounded = Int(round(clamped))
        if rounded != lastHapticStep {
            bpmFeedback.impactOccurred(intensity: 0.72)
            bpmFeedback.prepare()
            lastHapticStep = rounded
        }
    }

    private func commitBPMEntry() {
        let cleaned = bpmEntryText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty, let value = Double(cleaned) else {
            bpmEntryText = "\(Int(round(displayedBPM)))"
            return
        }
        handleBPMChange(value)
        bpmEntryText = "\(Int(round(displayedBPM)))"
    }

    private func syncMetronomeBPMToSettings(from bpm: Double) {
        updateMetronomeSettings { settings in
            settings.bpm = bpm
        }
    }

    private func toggleMute() {
        let current = services.metronomeEngine.masterVolume
        if current > 0.0001 {
            lastAudibleVolume = current
            applyVolume(0)
        } else {
            applyVolume(max(0.08, lastAudibleVolume))
        }
    }

    private func applyVolume(_ value: Double) {
        let clamped = max(0, min(1, value))
        if clamped > 0.0001 {
            lastAudibleVolume = clamped
        }
        updateMetronomeSettings { settings in
            settings.masterVolume = clamped
        }
    }

    private func updateMetronomeSettings(_ mutate: (inout MetronomeSettings) -> Void) {
        var settings = services.toolsSettings.metronome
        mutate(&settings)
        services.toolsSettings.metronome = settings
    }

    private func beginTunerPreviewHold(note: Int) {
        tunerHeldMIDINote = note
        tunerPreviewSynth.startSustainedMIDINote(note)
    }

    private func endTunerPreviewHold() {
        tunerHeldMIDINote = nil
        if let sustained = tunerSustainedMIDINote {
            tunerPreviewSynth.startSustainedMIDINote(sustained)
        } else {
            tunerPreviewSynth.stopSustainedMIDINote()
        }
    }

    private func latchTunerSustain(note: Int) {
        tunerSustainedMIDINote = note
        tunerPreviewSynth.startSustainedMIDINote(note)
        sustainFeedback.impactOccurred(intensity: 0.8)
        sustainFeedback.prepare()
    }

    private func toggleTunerSustain() {
        if tunerSustainedMIDINote != nil {
            tunerSustainedMIDINote = nil
            if let held = tunerHeldMIDINote {
                tunerPreviewSynth.startSustainedMIDINote(held)
            } else {
                tunerPreviewSynth.stopSustainedMIDINote()
            }
            sustainFeedback.impactOccurred(intensity: 0.65)
            sustainFeedback.prepare()
            return
        }

        if let note = tunerHeldMIDINote ?? services.tunerEngine.midiNote {
            latchTunerSustain(note: note)
        }
    }

    private func centsColor(_ cents: Double) -> Color {
        switch abs(cents) {
        case 0..<6: return .green
        case 6..<16: return .yellow
        default: return .orange
        }
    }

    @MainActor
    private func bootstrapInputsIfNeeded() async {
        guard !didBootstrapInputs else { return }
        didBootstrapInputs = true

        updateMetronomeSettings { settings in
            settings.grooveEnabled = false
        }

        midiLease = services.audioUsageCoordinator.acquireMIDI()
        micLease = await services.audioUsageCoordinator.acquireMicrophone(recordAudio: false)

        let currentBPM = services.metronomeEngine.bpm
        displayedBPM = currentBPM
        lastHapticStep = Int(round(currentBPM))
        lastAudibleVolume = max(0.08, services.metronomeEngine.masterVolume)
        services.liveTempoAnalyzer.targetBPM = currentBPM
    }
}

private enum BottomDropUpMenu: Hashable {
    case meter
    case subdivision
    case countIn
    case sound
}

struct PrecisionTempoSlider: View {
    let value: Double
    let isRunning: Bool
    let beatFlash: Bool
    var range: ClosedRange<Double> = 30...320
    let onValueChanged: (Double) -> Void

    @State private var dragStartValue: Double?
    @State private var dragStartLocation: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            let sliderHeight = geo.size.height
            let thumbDiameter = max(24, sliderHeight - 4)
            let availableWidth = max(1, geo.size.width - thumbDiameter)
            let normalized = normalizedValue(value)
            let thumbOffset = normalized * availableWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.accentColor.opacity(0.16))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.42),
                                Color.accentColor.opacity(beatFlash && isRunning ? 0.95 : 0.78)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: thumbOffset + thumbDiameter * 0.5)
                    }

                Circle()
                    .fill(.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(x: thumbOffset)
                    .shadow(color: .black.opacity(0.24), radius: 6, y: 3)
            }
            .frame(height: sliderHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if dragStartValue == nil {
                            dragStartValue = value
                            dragStartLocation = gesture.location
                        }

                        guard let startValue = dragStartValue else { return }

                        let horizontalDelta = Double((gesture.location.x - dragStartLocation.x) / availableWidth)
                        let verticalDelta = gesture.location.y - dragStartLocation.y
                        let scaledDelta = horizontalDelta * (range.upperBound - range.lowerBound) * precisionScale(for: verticalDelta)
                        let next = max(range.lowerBound, min(range.upperBound, startValue + scaledDelta))
                        onValueChanged(next)
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                    }
            )
        }
    }

    private func normalizedValue(_ value: Double) -> CGFloat {
        let clamped = max(range.lowerBound, min(range.upperBound, value))
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((clamped - range.lowerBound) / span)
    }

    private func precisionScale(for verticalDelta: CGFloat) -> Double {
        if verticalDelta < 0 {
            return max(0.08, 1.0 + Double(verticalDelta) / 220.0)
        }
        return min(2.8, 1.0 + Double(verticalDelta) / 120.0)
    }
}

private struct PitchAccuracyRing: View {
    let cents: Double
    let confidence: Double
    let detectedMIDINote: Int?
    let isSustainActive: Bool
    let onHoldStart: (Int) -> Void
    let onHoldEnd: () -> Void
    let onSustainSwipeUp: (Int) -> Void
    let onToggleSustain: () -> Void

    @State private var isHolding = false
    @State private var activeHoldMIDINote: Int?
    @State private var holdStartPoint: CGPoint = .zero
    @State private var touchStartPoint: CGPoint = .zero
    @State private var touchStartDate: Date?
    @State private var didTriggerSustainSwipe = false

    private var normalizedAccuracy: Double {
        max(0, min(1, 1 - abs(cents) / 35))
    }

    private var progress: Double {
        max(0.05, normalizedAccuracy * max(0.25, min(1, confidence)))
    }

    private var tintColor: Color {
        switch normalizedAccuracy {
        case 0.75...: .green
        case 0.45..<0.75: .yellow
        default: .red
        }
    }

    private var shouldShowSustainBadge: Bool {
        isHolding || isSustainActive
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 11)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.red, .yellow, .green]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(Int(round(normalizedAccuracy * 100)))%")
                    .font(.headline.monospacedDigit())
                Text("Pitch")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tintColor)
            }

            if shouldShowSustainBadge {
                TopInnerSemicircle()
                    .fill(isSustainActive ? Color.accentColor.opacity(0.94) : Color.white.opacity(0.18))
                    .frame(width: 88, height: 44)
                    .overlay(
                        TopInnerSemicircle()
                            .stroke(isSustainActive ? Color.accentColor : Color.white.opacity(0.28), lineWidth: 1)
                    )
                    .overlay {
                        VStack(spacing: 1) {
                            Text("Sustain")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isSustainActive ? Color.white : Color.primary)
                            if isHolding && !isSustainActive {
                                Text("swipe up")
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isSustainActive ? Color.white.opacity(0.9) : Color.primary.opacity(0.8))
                            }
                        }
                        .padding(.top, 6)
                    }
                    .offset(y: -42)
            }
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if touchStartDate == nil {
                        touchStartDate = Date()
                        touchStartPoint = gesture.location
                    }

                    if !isHolding {
                        if isSustainActive {
                            let elapsed = touchStartDate.map { Date().timeIntervalSince($0) } ?? 0
                            let moved = hypot(
                                gesture.location.x - touchStartPoint.x,
                                gesture.location.y - touchStartPoint.y
                            )
                            if elapsed < 0.14 && moved < 8 {
                                return
                            }
                        }

                        guard let note = detectedMIDINote else { return }
                        isHolding = true
                        activeHoldMIDINote = note
                        holdStartPoint = gesture.location
                        didTriggerSustainSwipe = false
                        onHoldStart(note)
                    }

                    guard
                        isHolding,
                        !didTriggerSustainSwipe,
                        let note = activeHoldMIDINote
                    else { return }

                    let upwardDelta = holdStartPoint.y - gesture.location.y
                    if upwardDelta >= 18 {
                        didTriggerSustainSwipe = true
                        onSustainSwipeUp(note)
                    }
                }
                .onEnded { _ in
                    if isHolding {
                        isHolding = false
                        activeHoldMIDINote = nil
                        didTriggerSustainSwipe = false
                        onHoldEnd()
                    } else if isSustainActive {
                        let elapsed = touchStartDate.map { Date().timeIntervalSince($0) } ?? 0
                        if elapsed <= 0.35 {
                            onToggleSustain()
                        }
                    }

                    touchStartDate = nil
                    touchStartPoint = .zero
                    holdStartPoint = .zero
                    didTriggerSustainSwipe = false
                }
        )
    }
}

private struct TopInnerSemicircle: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height * 2) * 0.5
        let center = CGPoint(x: rect.midX, y: rect.maxY)

        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: center.x + radius, y: rect.maxY))
        path.addLine(to: CGPoint(x: center.x - radius, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct VerticalVolumeRail: View {
    let volume: Double
    let onVolumeAdjust: (Double) -> Void

    @State private var dragStartValue: Double?
    @State private var dragStartLocation: CGPoint = .zero

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let railHeight = geo.size.height
                let trackWidth: CGFloat = 10
                let thumbDiameter: CGFloat = 12
                let activeHeight = max(thumbDiameter, railHeight * max(0.02, volume))

                ZStack(alignment: .bottom) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: trackWidth)

                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.82))
                        .frame(width: trackWidth, height: railHeight)
                        .mask(alignment: .bottom) {
                            Rectangle()
                                .frame(width: trackWidth, height: activeHeight)
                        }

                    Circle()
                        .fill(.white)
                        .frame(width: thumbDiameter, height: thumbDiameter)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                        )
                        .offset(y: -(activeHeight - thumbDiameter * 0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if dragStartValue == nil {
                                dragStartValue = volume
                                dragStartLocation = gesture.location
                            }
                            guard let startValue = dragStartValue else { return }
                            let delta = Double((dragStartLocation.y - gesture.location.y) / max(1, railHeight))
                            let next = max(0, min(1, startValue + delta))
                            onVolumeAdjust(next)
                        }
                        .onEnded { _ in
                            dragStartValue = nil
                        }
                )
            }
            .frame(width: 20, height: 78)

            Text("\(Int(round(volume * 100)))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Image(systemName: volume <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
        )
    }
}

private struct CountInDotsOverlay: View {
    let beatsPerRow: Int
    let totalBeats: Int
    let completedBeats: Int

    private var rows: [[Int]] {
        let safePerRow = max(1, beatsPerRow)
        let all = Array(0..<max(0, totalBeats))
        guard !all.isEmpty else { return [] }

        var result: [[Int]] = []
        var index = 0
        while index < all.count {
            let end = min(all.count, index + safePerRow)
            result.append(Array(all[index..<end]))
            index = end
        }
        return result
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Count-In")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { dotIndex in
                            Circle()
                                .fill(dotIndex < completedBeats ? Color.accentColor : Color.clear)
                                .overlay(
                                    Circle()
                                        .stroke(Color.accentColor.opacity(0.85), lineWidth: 1.4)
                                )
                                .frame(width: 20, height: 20)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
    }
}

private struct BottomSquareControlButton: View {
    let icon: String
    let title: String
    let detail: String
    var symbolOnlyDetail: Bool = false
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(symbolOnlyDetail ? .title3.weight(.semibold) : .caption.weight(.semibold))
                    .lineLimit(symbolOnlyDetail ? 1 : 2)
                    .minimumScaleFactor(0.62)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 90)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.28) : Color.accentColor.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.8) : Color.accentColor.opacity(0.24), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DropUpActionButton: View {
    let icon: String
    let title: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.28) : Color.accentColor.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.8) : Color.accentColor.opacity(0.24), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TunerSettingsSheet: View {
    @Binding var settings: TunerSettings
    let onReset: () -> Void

    private let pitchClassNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Tuning") {
                    HStack {
                        Text("A4")
                        Slider(value: $settings.a4Hz, in: 430...450, step: 0.5)
                        Text(String(format: "%.1f Hz", settings.a4Hz))
                            .font(.footnote.monospacedDigit())
                            .frame(width: 68, alignment: .trailing)
                    }

                    Picker("Temperament", selection: $settings.temperament) {
                        ForEach(TunerTemperament.allCases) { temperament in
                            Text(temperament.displayName).tag(temperament)
                        }
                    }

                    if settings.temperament != .equal {
                        Picker("Temperament Root", selection: $settings.temperamentRootPitchClass) {
                            ForEach(0..<12, id: \.self) { pitchClass in
                                Text(pitchClassNames[pitchClass]).tag(pitchClass)
                            }
                        }
                    }
                }

                Section("Tracking") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tone Change Sensitivity")
                        Slider(value: $settings.toneChangeSensitivity, in: 0...1)
                        Text(settings.toneChangeSensitivity < 0.34 ? "Slower note switching" : (settings.toneChangeSensitivity < 0.67 ? "Balanced switching" : "Faster note switching"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confidence Gate")
                        Slider(value: $settings.confidenceGate, in: 0.2...0.95)
                        Text("Ignore unstable detections below \(Int(settings.confidenceGate * 100))% confidence.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Reset Tuner Defaults", role: .destructive) {
                        onReset()
                    }
                }
            }
            .navigationTitle("Tuner Settings")
        }
    }
}

struct MetronomeSettingsSheet: View {
    @Binding var settings: MetronomeSettings
    let onReset: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Meter") {
                    Stepper("Top: \(settings.meter.top)", value: Binding(
                        get: { settings.meter.top },
                        set: { settings.meter = MeterSignature(top: $0, bottom: settings.meter.bottom) }
                    ), in: 1...32)

                    Picker("Bottom", selection: Binding(
                        get: { settings.meter.bottom },
                        set: { settings.meter = MeterSignature(top: settings.meter.top, bottom: $0) }
                    )) {
                        Text("4").tag(4)
                        Text("8").tag(8)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Click") {
                    Picker("Subdivision", selection: $settings.subdivision) {
                        ForEach(MetronomeSubdivision.allCases) { option in
                            Text(option.notationSymbol).tag(option)
                        }
                    }

                    Stepper("Count-in Bars: \(settings.countInBars)", value: $settings.countInBars, in: 0...4)

                    Toggle("Different Subdivision Sound", isOn: $settings.subdivisionUsesAlternateClick)

                    Picker("Sound", selection: $settings.soundSet) {
                        ForEach(MetronomeSoundSet.allCases) { set in
                            Text(set.displayName).tag(set)
                        }
                    }
                }

                Section("Output") {
                    HStack {
                        Text("Master Volume")
                        Slider(value: $settings.masterVolume, in: 0...1)
                    }

                    Toggle("Haptics", isOn: $settings.hapticsEnabled)
                }

                Section {
                    Button("Reset Metronome Defaults", role: .destructive) {
                        onReset()
                    }
                }
            }
            .navigationTitle("Metronome Settings")
        }
    }
}

private struct LiveMetricTile: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
