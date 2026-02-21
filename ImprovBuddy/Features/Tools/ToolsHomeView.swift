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

    @State private var showTunerSettings = false
    @State private var showMetronomeSettings = false
    @State private var didBootstrapInputs = false
    @State private var displayedBPM = MetronomeSettings.default.bpm
    @State private var beatFlash = false
    @State private var lastHapticStep = Int(round(MetronomeSettings.default.bpm))
    @State private var lastAudibleVolume = MetronomeSettings.default.masterVolume
    @State private var activeDropUp: BottomDropUpMenu?

    @State private var micLease: AudioUsageCoordinator.LeaseToken?
    @State private var midiLease: AudioUsageCoordinator.LeaseToken?
    private let bpmFeedback = UIImpactFeedbackGenerator(style: .rigid)
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
        .task {
            await bootstrapInputsIfNeeded()
        }
        .onAppear {
            displayedBPM = services.metronomeEngine.bpm
            lastHapticStep = Int(round(displayedBPM))
            lastAudibleVolume = max(0.05, services.metronomeEngine.masterVolume)
            bpmFeedback.prepare()
        }
        .onChange(of: services.metronomeEngine.bpm) { _, newValue in
            displayedBPM = newValue
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
            micLease = nil
            midiLease = nil
            didBootstrapInputs = false
            activeDropUp = nil
        }
    }

    private var studioSurface: some View {
        VStack(spacing: 14) {
            tunerSection
                .frame(minHeight: 194)
            metronomeSection
            analysisSection
        }
    }

    private var tunerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tuner")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    showTunerSettings = true
                } label: {
                    Image(systemName: "tuningfork")
                        .font(.body.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tuner Settings")
            }

            HStack(alignment: .center, spacing: 16) {
                PitchAccuracyRing(
                    cents: services.tunerEngine.cents,
                    confidence: services.tunerEngine.confidence
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

    private var metronomeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(Int(round(displayedBPM))) BPM")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()

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
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Metronome Settings")
            }

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
                    icon: "music.note.list",
                    title: services.metronomeEngine.soundSet.displayName,
                    isActive: activeDropUp == .sound
                ) {
                    toggleDropUp(.sound)
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) {
                    if activeDropUp == .sound {
                        columnOverlayMenu(for: .sound)
                            .offset(y: -218)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .zIndex(activeDropUp == .sound ? 20 : 0)

                VolumeGestureChip(
                    volume: services.metronomeEngine.masterVolume,
                    onToggleMute: {
                        toggleMute()
                    },
                    onVolumeAdjust: { value in
                        applyVolume(value)
                    }
                )
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

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BPM Analysis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    toggleLiveTempoAnalyzer()
                } label: {
                    Text(services.liveTempoAnalyzer.isRunning ? "Stop" : "Start")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                LiveMetricTile(
                    title: "Auto",
                    value: String(format: "%.1f", services.liveTempoAnalyzer.autoBPM),
                    unit: "BPM"
                )
                LiveMetricTile(
                    title: "Error",
                    value: String(format: "%.1f", services.liveTempoAnalyzer.latestErrorMs),
                    unit: "ms"
                )
                LiveMetricTile(
                    title: "Input",
                    value: services.liveTempoAnalyzer.lastOnsetSource?.rawValue.uppercased() ?? "-",
                    unit: services.liveTempoAnalyzer.driftState == .stable ? "Stable" : "Drift"
                )
            }
        }
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
            .overlay(alignment: .top) {
                if activeDropUp == .meter {
                    columnOverlayMenu(for: .meter)
                        .offset(y: -208)
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
            .overlay(alignment: .top) {
                if activeDropUp == .subdivision {
                    columnOverlayMenu(for: .subdivision)
                        .offset(y: -182)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .zIndex(activeDropUp == .subdivision ? 20 : 0)

            BottomSquareControlButton(
                icon: "hand.tap.fill",
                title: "Tap Tempo",
                detail: "\(Int(round(displayedBPM)))"
            ) {
                activeDropUp = nil
                if let tappedBPM = services.metronomeEngine.registerTapTempo() {
                    handleBPMChange(tappedBPM)
                }
            }

            BottomSquareControlButton(
                icon: "countdown",
                title: "Count-In",
                detail: "\(services.metronomeEngine.countInBars)",
                isActive: activeDropUp == .countIn
            ) {
                toggleDropUp(.countIn)
            }
            .overlay(alignment: .top) {
                if activeDropUp == .countIn {
                    columnOverlayMenu(for: .countIn)
                        .offset(y: -182)
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
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(MetronomeSoundSet.allCases) { soundSet in
                            overlayOptionButton(
                                label: soundSet.displayName,
                                selected: soundSet == services.metronomeEngine.soundSet
                            ) {
                                updateMetronomeSettings { settings in
                                    settings.soundSet = soundSet
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 176)
            }
        }
        .padding(8)
        .frame(width: kind == .sound ? 132 : 118)
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
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            withAnimation(.easeOut(duration: 0.16)) {
                activeDropUp = nil
            }
        } label: {
            Text(label)
                .font(largeSymbol ? .title3.weight(.semibold) : .caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, largeSymbol ? 10 : 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.86) : Color.white.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleDropUp(_ menu: BottomDropUpMenu) {
        withAnimation(.easeOut(duration: 0.16)) {
            activeDropUp = activeDropUp == menu ? nil : menu
        }
    }

    private func toggleLiveTempoAnalyzer() {
        if services.liveTempoAnalyzer.isRunning {
            services.liveTempoAnalyzer.stop()
        } else {
            services.liveTempoAnalyzer.targetBPM = services.metronomeEngine.bpm
            services.liveTempoAnalyzer.start()
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
                    .fill(Color.white.opacity(0.12))

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
        }
    }
}

private struct VolumeGestureChip: View {
    let volume: Double
    let onToggleMute: () -> Void
    let onVolumeAdjust: (Double) -> Void

    @State private var showOverlay = false
    @State private var dragStartY: CGFloat = 0
    @State private var dragStartVolume: Double = 0
    @State private var dragStartDate: Date?

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 6) {
                Image(systemName: volume <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3.weight(.bold))
                Text(volume <= 0.001 ? "Muted" : "\(Int(round(volume * 100)))%")
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.accentColor.opacity(showOverlay ? 0.65 : 0.12), lineWidth: 1)
            )

            if showOverlay {
                VStack(spacing: 6) {
                    Text("\(Int(round(volume * 100)))%")
                        .font(.caption.monospacedDigit())
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.18))
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.accentColor)
                                .frame(height: geo.size.height * max(0.02, volume))
                        }
                    }
                    .frame(width: 12, height: 72)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .offset(y: -116)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if dragStartDate == nil {
                        dragStartDate = Date()
                        dragStartY = gesture.location.y
                        dragStartVolume = volume
                    }

                    guard let startDate = dragStartDate else { return }
                    let elapsed = Date().timeIntervalSince(startDate)
                    guard elapsed > 0.18 else { return }

                    showOverlay = true
                    let delta = Double((dragStartY - gesture.location.y) / 130)
                    let next = max(0, min(1, dragStartVolume + delta))
                    onVolumeAdjust(next)
                }
                .onEnded { gesture in
                    let elapsed = dragStartDate.map { Date().timeIntervalSince($0) } ?? 0
                    let moved = hypot(gesture.translation.width, gesture.translation.height)
                    if elapsed < 0.18 && moved < 8 {
                        onToggleMute()
                    }
                    dragStartDate = nil
                    showOverlay = false
                },
        )
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
                    .font(symbolOnlyDetail ? .title3.weight(.semibold) : .callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 90)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.24) : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.65) : Color.white.opacity(0.07), lineWidth: 1)
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
                    .fill(isActive ? Color.accentColor.opacity(0.24) : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.65) : Color.white.opacity(0.07), lineWidth: 1)
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
