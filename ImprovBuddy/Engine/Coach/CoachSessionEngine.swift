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
    @Published private(set) var currentSectionLabel: String = ""
    @Published private(set) var currentChordSymbol: String = "-"

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
    private var currentTheoryContext: TheoryContext = .default

    private var sessionClockTask: Task<Void, Never>?
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

    init(eventBus: UnifiedEventBus, theoryResolver: TheoryResolver? = nil) {
        self.eventBus = eventBus
        self.theoryResolver = theoryResolver
        bindInputEvents()
    }

    func startSession(configuration: SessionConfiguration) {
        resetSessionState()
        config = configuration
        targetTempoBPM = configuration.targetTempoBPM
        currentTheoryContext = configuration.theoryContext

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
        currentSectionLabel = position.sectionLabel ?? "-"
        currentChordSymbol = formTracker.currentMeasure(at: elapsedTime)?.chordSymbol ?? "-"
    }

    private func resetSessionState() {
        eventBus.reset()

        isRunning = false
        isPaused = false

        elapsedTime = 0
        currentMeasureIndex = 0
        currentSectionLabel = ""
        currentChordSymbol = "-"

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
