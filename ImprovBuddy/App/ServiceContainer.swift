import Combine
import Foundation

@MainActor
final class ServiceContainer: ObservableObject {
    let eventBus = UnifiedEventBus()

    let toolsSettings = ToolsSettingsStore()
    let midiManager: MIDIManager
    let audioManager: AudioEngineManager
    let metronomeEngine: MetronomeEngine
    let bpmDetector = BPMDetector()
    let liveTempoAnalyzer: LiveTempoAnalyzerEngine
    let audioUsageCoordinator: AudioUsageCoordinator
    var tunerEngine: TunerEngine
    let theoryKnowledgeBase: TheoryKnowledgeBase
    let theoryResolver: TheoryResolver

    private var cancellables = Set<AnyCancellable>()

    init() {
        theoryKnowledgeBase = TheoryKnowledgeBase.load()
        theoryResolver = TheoryResolver(knowledgeBase: theoryKnowledgeBase)

        midiManager = MIDIManager(eventBus: eventBus)
        audioManager = AudioEngineManager(eventBus: eventBus)
        metronomeEngine = MetronomeEngine()
        liveTempoAnalyzer = LiveTempoAnalyzerEngine(eventBus: eventBus)
        audioUsageCoordinator = AudioUsageCoordinator(audioManager: audioManager, midiManager: midiManager)
        tunerEngine = TunerEngine(eventBus: eventBus, settingsStore: toolsSettings)

        metronomeEngine.apply(settings: toolsSettings.metronome)

        // Relay child engine/state updates so views observing ServiceContainer refresh.
        Publishers.MergeMany(
            toolsSettings.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            metronomeEngine.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            liveTempoAnalyzer.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            tunerEngine.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            audioManager.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            audioUsageCoordinator.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)

        toolsSettings.$metronome
            .sink { [weak self] settings in
                self?.metronomeEngine.apply(settings: settings)
            }
            .store(in: &cancellables)

        eventBus.onsetPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] onset in
                self?.bpmDetector.ingestOnset(time: onset.time)
            }
            .store(in: &cancellables)
    }
}
