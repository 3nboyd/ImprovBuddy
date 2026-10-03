import Combine
import Foundation

@MainActor
final class PracticeSandboxEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var liveBPM: Double = 0
    @Published private(set) var latestErrorMs: Double = 0
    @Published private(set) var driftState: TempoDriftState = .stable

    var targetBPM: Double = 100
    var inputMode: InputMode = .both

    private let eventBus: UnifiedEventBus
    private var tempoAnalyzer: TempoAnalyzer?
    private var startUptime: TimeInterval?
    private var lastMidiOnset: TimeInterval = -100
    private var cancellables = Set<AnyCancellable>()

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
        isRunning = true
        liveBPM = targetBPM
        latestErrorMs = 0
        driftState = .stable
    }

    func stop() {
        isRunning = false
        tempoAnalyzer = nil
        startUptime = nil
        lastMidiOnset = -100
    }

    private func handleOnset(_ onset: OnsetEvent) {
        guard isRunning, let tempoAnalyzer, let startUptime else { return }

        let sessionTime = onset.time - startUptime
        guard sessionTime >= 0 else { return }

        if onset.source == .midi { lastMidiOnset = sessionTime }

        if inputMode == .midi, onset.source != .midi { return }
        if inputMode == .mic, onset.source != .mic { return }
        if inputMode == .both, onset.source == .mic, sessionTime - lastMidiOnset < 0.15 { return }

        let snapshot = tempoAnalyzer.processOnset(time: sessionTime)
        liveBPM = snapshot.liveBPM
        latestErrorMs = snapshot.latestErrorMs
        driftState = snapshot.isDrifting ? .drifting : .stable
    }
}
