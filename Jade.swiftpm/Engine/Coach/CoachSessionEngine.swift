import Combine
import Foundation

struct SessionConfiguration {
    var song: Song
    var inputMode: InputMode
    var targetTempoBPM: Double
    var feel: FeelType
    var timeSignatureTop: Int
    var timeSignatureBottom: Int
    var displayKey: String
    var countInBeats: Int
    var subdivision: GridSubdivision
    var theoryContext: TheoryContext
}

enum TempoDriftState: String {
    case stable
    case drifting
}

enum PocketState: String {
    case ahead
    case centered
    case behind
}

@MainActor
final class CoachSessionEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false

    @Published private(set) var targetTempoBPM: Double = 120
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var currentMeasureIndex: Int = 0
    @Published private(set) var currentChorusIndex: Int = 0
    @Published private(set) var currentSectionLabel: String = ""
    @Published private(set) var currentChordSymbol: String = "-"
    @Published private(set) var displayKeyName: String = TheoryKey.defaultKey.name
    @Published private(set) var formMeasures: [Measure] = []
    @Published private(set) var isConstantMetEnabled = false
    @Published private(set) var metronomeSoundSet: MetronomeSoundSet = .woodblock
    @Published private(set) var metronomeVolume: Double = 0.8
    @Published private(set) var targetChorusCount: Int = 4

    @Published private(set) var liveEstimatedBPM: Double = 0
    @Published private(set) var tempoDriftState: TempoDriftState = .stable
    @Published private(set) var latestTimingErrorMs: Double = 0
    @Published private(set) var pocketState: PocketState = .centered
    @Published private(set) var swingRatio: Double = 2.0
    @Published private(set) var harmonyState: HarmonyClass = .chordTone
    @Published private(set) var coachPrompt: String = "Connect an input and start playing."

    @Published private(set) var latestReport: ProfessorReportSections?

    private let eventBus: UnifiedEventBus
    private var cancellables = Set<AnyCancellable>()

    private var config: SessionConfiguration?
    private var tempoAnalyzer: TempoAnalyzer?
    private var swingAnalyzer: SwingAnalyzer?
    private var harmonyAnalyzer = HarmonyAnalyzer()
    private var formTracker: FormPositionTracker?
    private var promptGenerator = CoachPromptGenerator()
    private let theoryResolver: TheoryResolver?
    private let metronomeEngine: MetronomeEngine?
    private var currentTheoryContext: TheoryContext = .default

    private var sessionClockTask: Task<Void, Never>?
    private var metronomeAutoStopTask: Task<Void, Never>?
    private var sessionStartUptime: TimeInterval?
    private var sessionStartDate: Date?
    private var accumulatedPausedTime: TimeInterval = 0
    private var pauseStartedUptime: TimeInterval?

    private var lastMidiOnsetTime: TimeInterval = -100
    private var lastMidiPitchTime: TimeInterval = -100

    private var onsetTimes: [TimeInterval] = []
    private var bpmSeries: [TimeValuePair] = []
    private var timingErrorSeries: [TimeValuePair] = []
    private var swingSeries: [TimeValuePair] = []
    private var pitchSeries: [PitchTracePoint] = []

    init(
        eventBus: UnifiedEventBus,
        theoryResolver: TheoryResolver? = nil,
        metronomeEngine: MetronomeEngine? = nil
    ) {
        self.eventBus = eventBus
        self.theoryResolver = theoryResolver
        self.metronomeEngine = metronomeEngine
        if let settings = metronomeEngine?.exportSettings() {
            metronomeSoundSet = settings.soundSet
            metronomeVolume = settings.masterVolume
        }
        bindInputEvents()
    }

    func startSession(configuration: SessionConfiguration) {
        resetSessionState()
        config = configuration
        targetTempoBPM = configuration.targetTempoBPM
        currentTheoryContext = configuration.theoryContext
        displayKeyName = configuration.displayKey
        currentTheoryContext.concertKeyName = configuration.displayKey
        formMeasures = configuration.song.flattenedForm

        tempoAnalyzer = TempoAnalyzer(
            targetBPM: configuration.targetTempoBPM,
            subdivision: configuration.subdivision
        )

        swingAnalyzer = configuration.feel == .swing
            ? SwingAnalyzer(targetBPM: configuration.targetTempoBPM)
            : nil

        formTracker = FormPositionTracker(
            measures: configuration.song.flattenedForm,
            timeSignatureTop: configuration.timeSignatureTop,
            targetBPM: configuration.targetTempoBPM
        )

        isRunning = true
        isPaused = false
        let countInSeconds = Double(configuration.countInBeats) * (60.0 / configuration.targetTempoBPM)
        sessionStartUptime = ProcessInfo.processInfo.systemUptime + countInSeconds
        sessionStartDate = Date().addingTimeInterval(countInSeconds)
        accumulatedPausedTime = 0

        startSessionMetronome(configuration: configuration, countInSeconds: countInSeconds)
        runSessionClock()
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        pauseStartedUptime = ProcessInfo.processInfo.systemUptime
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        if let pauseStartedUptime {
            accumulatedPausedTime += ProcessInfo.processInfo.systemUptime - pauseStartedUptime
        }
        self.pauseStartedUptime = nil
    }

    func endSession() -> PracticeSession? {
        guard let config, let tempoAnalyzer else { return nil }

        isRunning = false
        isPaused = false
        sessionClockTask?.cancel()
        sessionClockTask = nil
        metronomeAutoStopTask?.cancel()
        metronomeAutoStopTask = nil
        metronomeEngine?.stop()

        let tempoSummary = tempoAnalyzer.summaryStats()
        let harmonySummary = harmonyAnalyzer.summaryStats()
        let swingSummary = swingAnalyzer?.summaryStats() ?? SwingStats(averageRatio: 1, consistencyStdDev: 0)

        let pocket = pocketStats(from: tempoAnalyzer.allTimingErrors())

        var summary = SessionSummaryMetrics(
            tempoDrift: tempoSummary,
            pocket: pocket,
            swing: swingSummary,
            harmony: harmonySummary,
            professorNotesText: "",
            recommendedDrillIDs: []
        )

        var report = ProfessorNotesGenerator.generate(summary: summary)

        if let songChord = config.song.flattenedForm.first?.parsedChord ?? config.song.flattenedForm.first.flatMap({ ChordParser.parse(symbol: $0.chordSymbol) }),
           let prompt = theoryResolver?.recommendationText(chord: songChord, context: currentTheoryContext) {
            report.opportunities.append("Theory focus: \(prompt)")
            if report.opportunities.count > 3 {
                report.opportunities = Array(report.opportunities.prefix(3))
            }
        }

        latestReport = report

        summary.professorNotesText = report.fullText
        summary.recommendedDrillIDs = report.nextDrills.map(\.id)

        let session = PracticeSession(
            songID: config.song.id,
            startedAt: sessionStartDate ?? .now,
            endedAt: .now,
            inputMode: config.inputMode,
            targetTempoBPM: config.targetTempoBPM,
            feel: config.feel,
            timeSignatureTop: config.timeSignatureTop,
            timeSignatureBottom: config.timeSignatureBottom,
            onsetTimes: onsetTimes,
            estimatedBPMOverTime: bpmSeries,
            timingErrorOverTimeMs: timingErrorSeries,
            swingRatioOverTime: swingSeries,
            detectedPitchOverTime: pitchSeries,
            chordMatchStateOverTime: harmonyAnalyzer.harmonyTimeline,
            summary: summary,
            theoryContext: currentTheoryContext
        )

        return session
    }

    func jumpToBar(_ barNumber: Int) {
        formTracker?.jumpToBar(barNumber, at: elapsedTime)
    }

    func restartChorus() {
        formTracker?.restartChorus(at: elapsedTime)
    }

    func setTargetChorusCount(_ count: Int) {
        targetChorusCount = max(1, min(32, count))
    }

    func updateDisplayKeyName(_ keyName: String) {
        guard TheoryKey.all.contains(where: { $0.name == keyName }) else { return }
        displayKeyName = keyName
        currentTheoryContext.concertKeyName = keyName
        if let currentMeasure = formTracker?.currentMeasure(at: elapsedTime) {
            currentChordSymbol = displayedChordSymbol(for: currentMeasure)
        }
    }

    func displayedChordSymbol(for measure: Measure) -> String {
        transposeChordSymbol(measure.chordSymbol)
    }

    func setConstantMetronomeEnabled(_ enabled: Bool) {
        isConstantMetEnabled = enabled
        guard let metronomeEngine else { return }
        metronomeAutoStopTask?.cancel()
        metronomeAutoStopTask = nil

        if enabled {
            if !metronomeEngine.isRunning {
                var settings = metronomeEngine.exportSettings()
                settings.countInBars = 0
                metronomeEngine.apply(settings: settings)
                metronomeEngine.start()
            }
        } else if metronomeEngine.isRunning {
            metronomeEngine.stop()
        }
    }

    func setMetronomeSoundSet(_ soundSet: MetronomeSoundSet) {
        guard let metronomeEngine else { return }
        var settings = metronomeEngine.exportSettings()
        settings.soundSet = soundSet
        metronomeEngine.apply(settings: settings)
        metronomeSoundSet = soundSet
    }

    func setMetronomeVolume(_ volume: Double) {
        guard let metronomeEngine else { return }
        let clamped = max(0, min(1, volume))
        var settings = metronomeEngine.exportSettings()
        settings.masterVolume = clamped
        metronomeEngine.apply(settings: settings)
        metronomeVolume = clamped
    }

    func resetForNextSession() {
        latestReport = nil
    }

    private func bindInputEvents() {
        eventBus.onsetPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] onset in
                self?.handleOnsetEvent(onset)
            }
            .store(in: &cancellables)

        eventBus.pitchPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pitch in
                self?.handlePitchEvent(pitch)
            }
            .store(in: &cancellables)
    }

    private func handleOnsetEvent(_ event: OnsetEvent) {
        guard isRunning, !isPaused, let config, let tempoAnalyzer else { return }
        let sessionTime = sessionElapsed(forRawInputTime: event.time)
        guard sessionTime >= 0 else { return }

        if event.source == .midi { lastMidiOnsetTime = sessionTime }

        if config.inputMode == .midi, event.source != .midi {
            return
        }

        if config.inputMode == .both,
           event.source == .mic,
           sessionTime - lastMidiOnsetTime < 0.15 {
            return
        }

        let snapshot = tempoAnalyzer.processOnset(time: sessionTime)
        liveEstimatedBPM = snapshot.liveBPM
        latestTimingErrorMs = snapshot.latestErrorMs
        tempoDriftState = snapshot.isDrifting ? .drifting : .stable

        pocketState = if snapshot.signedBiasMs < -10 {
            .ahead
        } else if snapshot.signedBiasMs > 10 {
            .behind
        } else {
            .centered
        }

        onsetTimes.append(sessionTime)
        bpmSeries.append(TimeValuePair(time: sessionTime, value: snapshot.liveBPM))
        timingErrorSeries.append(TimeValuePair(time: sessionTime, value: snapshot.latestErrorMs))

        if config.feel == .swing,
           let swingSnapshot = swingAnalyzer?.processOnset(time: sessionTime) {
            swingRatio = swingSnapshot.ratio
            swingSeries.append(TimeValuePair(time: sessionTime, value: swingSnapshot.ratio))
        }

        let liveState = LiveCoachingState(
            tempo: snapshot,
            harmony: harmonyAnalyzer.summaryStats()
        )

        if let prompt = promptGenerator.nextPromptIfNeeded(at: sessionTime, state: liveState) {
            coachPrompt = prompt
        } else if
            liveState.harmony.downbeatChordTonePct < 0.45,
            let formTracker,
            let chord = formTracker.currentMeasure(at: sessionTime)?.parsedChord,
            let theoryPrompt = theoryResolver?.recommendationText(chord: chord, context: currentTheoryContext) {
            coachPrompt = theoryPrompt
        }
    }

    private func handlePitchEvent(_ event: PitchEvent) {
        guard isRunning, !isPaused, let config, let formTracker else { return }
        let sessionTime = sessionElapsed(forRawInputTime: event.time)
        guard sessionTime >= 0 else { return }

        if event.source == .midi { lastMidiPitchTime = sessionTime }

        if config.inputMode == .midi, event.source != .midi {
            return
        }

        if config.inputMode == .both,
           event.source == .mic,
           sessionTime - lastMidiPitchTime < 0.2 {
            return
        }

        guard let chord = formTracker.currentMeasure(at: sessionTime)?.parsedChord
            ?? ChordParser.parse(symbol: formTracker.currentMeasure(at: sessionTime)?.chordSymbol ?? "") else {
            return
        }

        let allowedScalePitchClasses = theoryResolver?.pitchClassesForPrimaryScale(
            chord: chord,
            context: currentTheoryContext
        )

        let strongBeatTime = formTracker.nearestStrongBeatTime(for: sessionTime)
        let result = harmonyAnalyzer.process(
            pitchEvent: PitchEvent(
                time: sessionTime,
                midiNote: event.midiNote,
                confidence: event.confidence,
                source: event.source
            ),
            chord: chord,
            nearestStrongBeatTime: strongBeatTime,
            allowedScalePitchClasses: allowedScalePitchClasses
        )

        harmonyState = result.state
        pitchSeries.append(PitchTracePoint(time: sessionTime, midiNote: event.midiNote, confidence: event.confidence, source: event.source))
    }

    private func runSessionClock() {
        sessionClockTask?.cancel()

        sessionClockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRunning else { break }
                self.tick()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func tick() {
        guard isRunning, let sessionStartUptime else { return }

        if isPaused {
            return
        }

        let elapsedSinceStart = ProcessInfo.processInfo.systemUptime - sessionStartUptime - accumulatedPausedTime
        elapsedTime = max(0, elapsedSinceStart)

        guard let formTracker else { return }
        let position = formTracker.currentPosition(at: elapsedTime)
        currentMeasureIndex = position.measureIndex
        currentChorusIndex = position.chorusIndex
        currentSectionLabel = position.sectionLabel ?? "-"
        if let measure = formTracker.currentMeasure(at: elapsedTime) {
            currentChordSymbol = displayedChordSymbol(for: measure)
        } else {
            currentChordSymbol = "-"
        }

        if !isPaused,
           targetChorusCount > 0,
           position.chorusIndex + 1 >= targetChorusCount,
           position.measureIndex == max(0, formMeasures.count - 1),
           position.progressInMeasure >= 0.98 {
            pause()
            coachPrompt = "Loop target reached. Resume or increase choruses."
        }
    }

    private func startSessionMetronome(
        configuration: SessionConfiguration,
        countInSeconds: TimeInterval
    ) {
        guard let metronomeEngine else { return }

        metronomeAutoStopTask?.cancel()
        metronomeAutoStopTask = nil

        var settings = metronomeEngine.exportSettings()
        settings.bpm = configuration.targetTempoBPM
        settings.meter = MeterSignature(top: configuration.timeSignatureTop, bottom: configuration.timeSignatureBottom)
        settings.subdivision = .quarter
        settings.countInBars = barsForCountIn(
            countInBeats: configuration.countInBeats,
            beatsPerBar: configuration.timeSignatureTop
        )
        metronomeEngine.apply(settings: settings)
        metronomeSoundSet = settings.soundSet
        metronomeVolume = settings.masterVolume

        let shouldRun = settings.countInBars > 0 || isConstantMetEnabled
        guard shouldRun else { return }

        metronomeEngine.start()

        if !isConstantMetEnabled {
            let stopDelay = max(0, countInSeconds) + 0.12
            metronomeAutoStopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(stopDelay * 1_000_000_000))
                guard let self else { return }
                guard self.isRunning, !self.isConstantMetEnabled else { return }
                self.metronomeEngine?.stop()
            }
        }
    }

    private func barsForCountIn(countInBeats: Int, beatsPerBar: Int) -> Int {
        guard countInBeats > 0 else { return 0 }
        let barSize = max(1, beatsPerBar)
        return max(1, Int(ceil(Double(countInBeats) / Double(barSize))))
    }

    private func transposeChordSymbol(_ symbol: String) -> String {
        let sourceKey = TheoryKey.byName(config?.displayKey ?? TheoryKey.defaultKey.name)
        let targetKey = TheoryKey.byName(displayKeyName)
        let semitoneOffset = Chord.normalizePitchClass(targetKey.rootPitchClass - sourceKey.rootPitchClass)

        guard semitoneOffset != 0 else {
            return TheoryDisplayFormatter.displaySymbol(symbol)
        }

        let raw = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return symbol }

        let parts = raw.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let head = parts.first else {
            return TheoryDisplayFormatter.displaySymbol(symbol)
        }

        guard let (rootToken, descriptor) = splitRootToken(from: head),
              let rootPitchClass = pitchClass(for: rootToken) else {
            return TheoryDisplayFormatter.displaySymbol(symbol)
        }

        let preferSharps = TheoryKey.byName(displayKeyName).rootAccidental == "#"
        let transposedRoot = noteName(
            for: rootPitchClass + semitoneOffset,
            preferSharps: preferSharps
        )

        var result = transposedRoot + descriptor

        if parts.count > 1, let bassPitchClass = pitchClass(for: parts[1]) {
            let transposedBass = noteName(
                for: bassPitchClass + semitoneOffset,
                preferSharps: preferSharps
            )
            result += "/\(transposedBass)"
        }

        return TheoryDisplayFormatter.displaySymbol(result)
    }

    private func splitRootToken(from text: String) -> (String, String)? {
        guard let first = text.first, ("A"..."G").contains(String(first).uppercased()) else {
            return nil
        }

        var root = String(first).uppercased()
        var remainder = String(text.dropFirst())

        if let accidental = remainder.first, accidental == "#" || accidental == "b" {
            root.append(accidental)
            remainder = String(remainder.dropFirst())
        }

        return (root, remainder)
    }

    private func pitchClass(for note: String) -> Int? {
        switch note.lowercased() {
        case "c": return 0
        case "c#", "db": return 1
        case "d": return 2
        case "d#", "eb": return 3
        case "e", "fb": return 4
        case "f", "e#": return 5
        case "f#", "gb": return 6
        case "g": return 7
        case "g#", "ab": return 8
        case "a": return 9
        case "a#", "bb": return 10
        case "b", "cb": return 11
        default: return nil
        }
    }

    private func noteName(for pitchClass: Int, preferSharps: Bool) -> String {
        let normalized = Chord.normalizePitchClass(pitchClass)
        let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
        return preferSharps ? sharpNames[normalized] : flatNames[normalized]
    }

    private func resetSessionState() {
        eventBus.reset()

        isRunning = false
        isPaused = false

        elapsedTime = 0
        currentMeasureIndex = 0
        currentChorusIndex = 0
        currentSectionLabel = ""
        currentChordSymbol = "-"
        displayKeyName = TheoryKey.defaultKey.name
        formMeasures = []
        targetChorusCount = 4

        liveEstimatedBPM = 0
        tempoDriftState = .stable
        latestTimingErrorMs = 0
        pocketState = .centered
        swingRatio = 2.0
        harmonyState = .chordTone
        coachPrompt = "Connect an input and start playing."

        tempoAnalyzer?.reset()
        swingAnalyzer?.reset()
        harmonyAnalyzer.reset()
        promptGenerator.reset()

        onsetTimes.removeAll(keepingCapacity: true)
        bpmSeries.removeAll(keepingCapacity: true)
        timingErrorSeries.removeAll(keepingCapacity: true)
        swingSeries.removeAll(keepingCapacity: true)
        pitchSeries.removeAll(keepingCapacity: true)

        sessionStartUptime = nil
        sessionStartDate = nil
        accumulatedPausedTime = 0
        pauseStartedUptime = nil
        metronomeAutoStopTask?.cancel()
        metronomeAutoStopTask = nil
        metronomeEngine?.stop()
        lastMidiOnsetTime = -100
        lastMidiPitchTime = -100
        currentTheoryContext = .default
    }

    private func pocketStats(from timingErrors: [Double]) -> PocketBiasStats {
        guard !timingErrors.isEmpty else {
            return PocketBiasStats(aheadPct: 0, behindPct: 0, centeredPct: 1, meanBiasMs: 0)
        }

        let ahead = timingErrors.filter { $0 < -8 }.count
        let behind = timingErrors.filter { $0 > 8 }.count
        let centered = timingErrors.count - ahead - behind
        let mean = timingErrors.reduce(0, +) / Double(timingErrors.count)

        return PocketBiasStats(
            aheadPct: Double(ahead) / Double(timingErrors.count),
            behindPct: Double(behind) / Double(timingErrors.count),
            centeredPct: Double(centered) / Double(timingErrors.count),
            meanBiasMs: mean
        )
    }

    private func sessionElapsed(forRawInputTime rawTime: TimeInterval) -> TimeInterval {
        guard let sessionStartUptime else { return -1 }
        return rawTime - sessionStartUptime - accumulatedPausedTime
    }
}
