import Combine
import Foundation

@MainActor
final class BPMDetector: ObservableObject {
    @Published private(set) var detectedBPM: Double = 0
    @Published private(set) var tappedBPM: Double = 0

    private var onsetTimes: [TimeInterval] = []
    private var tapTimes: [TimeInterval] = []

    func ingestOnset(time: TimeInterval) {
        onsetTimes.append(time)
        if onsetTimes.count > 20 {
            onsetTimes.removeFirst(onsetTimes.count - 20)
        }

        let intervals = zip(onsetTimes, onsetTimes.dropFirst()).map { $1 - $0 }.filter { $0 > 0.08 && $0 < 2.0 }
        guard !intervals.isEmpty else { return }

        let medianInterval = TempoAnalyzer.median(intervals)
        guard medianInterval > 0 else { return }

        let bpm = 60 / medianInterval
        detectedBPM = 0.25 * bpm + 0.75 * detectedBPM
    }

    func tap() {
        let now = ProcessInfo.processInfo.systemUptime
        tapTimes.append(now)
        if tapTimes.count > 8 {
            tapTimes.removeFirst(tapTimes.count - 8)
        }

        let intervals = zip(tapTimes, tapTimes.dropFirst()).map { $1 - $0 }
        guard intervals.count >= 2 else { return }

        let medianInterval = TempoAnalyzer.median(intervals)
        guard medianInterval > 0 else { return }

        tappedBPM = 60 / medianInterval
    }

    func reset() {
        onsetTimes.removeAll(keepingCapacity: true)
        tapTimes.removeAll(keepingCapacity: true)
        detectedBPM = 0
        tappedBPM = 0
    }
}

@MainActor
final class LiveTempoAnalyzerEngine: ObservableObject {
    @Published var inputMode: InputMode = .both
    @Published var targetBPM: Double = 120

    @Published private(set) var isRunning = false
    @Published private(set) var autoBPM: Double = 0
    @Published private(set) var tapBPM: Double = 0
    @Published private(set) var liveBPM: Double = 0
    @Published private(set) var latestErrorMs: Double = 0
    @Published private(set) var driftState: TempoDriftState = .stable
    @Published private(set) var onsetCount = 0
    @Published private(set) var lastOnsetSource: EventSource?

    let midiPriorityWindow: TimeInterval = 0.15

    private let eventBus: UnifiedEventBus
    private var cancellables = Set<AnyCancellable>()

    private var onsetTimes: [TimeInterval] = []
    private var tapTimes: [TimeInterval] = []
    private var tempoAnalyzer: TempoAnalyzer?
    private var startUptime: TimeInterval?
    private var lastMidiOnsetTime: TimeInterval = -100

    init(eventBus: UnifiedEventBus) {
        self.eventBus = eventBus

        eventBus.onsetPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] onset in
                self?.handleOnset(onset)
            }
            .store(in: &cancellables)
    }

    func start() {
        tempoAnalyzer = TempoAnalyzer(targetBPM: targetBPM, subdivision: .eighth)
        startUptime = ProcessInfo.processInfo.systemUptime
        onsetTimes.removeAll(keepingCapacity: true)
        onsetCount = 0
        autoBPM = 0
        liveBPM = targetBPM
        latestErrorMs = 0
        driftState = .stable
        lastOnsetSource = nil
        lastMidiOnsetTime = -100
        isRunning = true
    }

    func stop() {
        isRunning = false
        tempoAnalyzer = nil
        startUptime = nil
        lastMidiOnsetTime = -100
        lastOnsetSource = nil
    }

    func reset() {
        onsetTimes.removeAll(keepingCapacity: true)
        tapTimes.removeAll(keepingCapacity: true)
        onsetCount = 0
        autoBPM = 0
        tapBPM = 0
        liveBPM = targetBPM
        latestErrorMs = 0
        driftState = .stable
        lastOnsetSource = nil
        lastMidiOnsetTime = -100
        tempoAnalyzer?.reset()
    }

    func tapTempo() {
        let now = ProcessInfo.processInfo.systemUptime
        tapTimes.append(now)
        if tapTimes.count > 8 {
            tapTimes.removeFirst(tapTimes.count - 8)
        }

        let intervals = zip(tapTimes, tapTimes.dropFirst()).map { $1 - $0 }
        guard intervals.count >= 2 else { return }

        let medianInterval = TempoAnalyzer.median(intervals)
        guard medianInterval > 0 else { return }

        tapBPM = 60 / medianInterval
    }

    private func handleOnset(_ onset: OnsetEvent) {
        guard isRunning, let tempoAnalyzer, let startUptime else { return }

        let sessionTime = onset.time - startUptime
        guard sessionTime >= 0 else { return }

        if onset.source == .midi {
            lastMidiOnsetTime = sessionTime
        }

        if inputMode == .midi, onset.source != .midi {
            return
        }
        if inputMode == .mic, onset.source != .mic {
            return
        }
        if inputMode == .both, onset.source == .mic, sessionTime - lastMidiOnsetTime < midiPriorityWindow {
            return
        }

        onsetCount += 1
        lastOnsetSource = onset.source

        onsetTimes.append(sessionTime)
        if onsetTimes.count > 24 {
            onsetTimes.removeFirst(onsetTimes.count - 24)
        }

        let intervals = zip(onsetTimes, onsetTimes.dropFirst())
            .map { $1 - $0 }
            .filter { $0 > 0.08 && $0 < 2.0 }
        if !intervals.isEmpty {
            let medianInterval = TempoAnalyzer.median(intervals)
            if medianInterval > 0 {
                let raw = 60 / medianInterval
                autoBPM = autoBPM == 0 ? raw : (0.25 * raw + 0.75 * autoBPM)
            }
        }

        let snapshot = tempoAnalyzer.processOnset(time: sessionTime)
        liveBPM = snapshot.liveBPM
        latestErrorMs = snapshot.latestErrorMs
        driftState = snapshot.isDrifting ? .drifting : .stable
    }
}

@MainActor
final class AudioUsageCoordinator: ObservableObject {
    struct LeaseToken: Hashable {
        fileprivate let id: UUID
    }

    @Published private(set) var activeMicLeaseCount = 0
    @Published private(set) var activeMIDILeaseCount = 0
    @Published private(set) var lastErrorMessage: String?

    private let audioManager: AudioEngineManager
    private let midiManager: MIDIManager

    private enum LeaseKind {
        case mic
        case midi
    }

    private var leases: [UUID: LeaseKind] = [:]
    private var startedAudioInternally = false
    private var startedMIDIInternally = false

    init(audioManager: AudioEngineManager, midiManager: MIDIManager) {
        self.audioManager = audioManager
        self.midiManager = midiManager
    }

    func acquireMicrophone(recordAudio: Bool = false) async -> LeaseToken? {
        let granted = audioManager.micPermissionGranted
            ? true
            : await audioManager.requestMicrophonePermission()
        guard granted else {
            lastErrorMessage = AudioEngineError.microphonePermissionDenied.localizedDescription
            return nil
        }

        do {
            if !audioManager.isRunning {
                try audioManager.start(recordAudio: recordAudio)
                startedAudioInternally = true
            }
            let token = LeaseToken(id: UUID())
            leases[token.id] = .mic
            activeMicLeaseCount = leases.values.filter { $0 == .mic }.count
            lastErrorMessage = nil
            return token
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    func acquireMIDI() -> LeaseToken {
        if !midiManager.isRunning {
            midiManager.start()
            startedMIDIInternally = true
        }

        let token = LeaseToken(id: UUID())
        leases[token.id] = .midi
        activeMIDILeaseCount = leases.values.filter { $0 == .midi }.count
        return token
    }

    func release(_ token: LeaseToken?) {
        guard let token, let kind = leases.removeValue(forKey: token.id) else { return }

        switch kind {
        case .mic:
            activeMicLeaseCount = leases.values.filter { $0 == .mic }.count
            if activeMicLeaseCount == 0, startedAudioInternally {
                audioManager.stop()
                startedAudioInternally = false
            }

        case .midi:
            activeMIDILeaseCount = leases.values.filter { $0 == .midi }.count
            if activeMIDILeaseCount == 0, startedMIDIInternally {
                midiManager.stop()
                startedMIDIInternally = false
            }
        }
    }

    func releaseAll() {
        leases.removeAll(keepingCapacity: true)
        activeMicLeaseCount = 0
        activeMIDILeaseCount = 0

        if startedAudioInternally {
            audioManager.stop()
            startedAudioInternally = false
        }
        if startedMIDIInternally {
            midiManager.stop()
            startedMIDIInternally = false
        }
    }
}
