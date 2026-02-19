import Combine
import Foundation

@MainActor
final class ServiceContainer: ObservableObject {
    let eventBus = UnifiedEventBus()

    let midiManager: MIDIManager
    let audioManager: AudioEngineManager
    let metronomeEngine = MetronomeEngine()
    let bpmDetector = BPMDetector()
    var tunerEngine: TunerEngine
    let theoryKnowledgeBase: TheoryKnowledgeBase
    let theoryResolver: TheoryResolver

    private var cancellables = Set<AnyCancellable>()

    init() {
        theoryKnowledgeBase = TheoryKnowledgeBase.load()
        theoryResolver = TheoryResolver(knowledgeBase: theoryKnowledgeBase)

        midiManager = MIDIManager(eventBus: eventBus)
        audioManager = AudioEngineManager(eventBus: eventBus)
        tunerEngine = TunerEngine(eventBus: eventBus)

        eventBus.onsetPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] onset in
                self?.bpmDetector.ingestOnset(time: onset.time)
            }
            .store(in: &cancellables)
    }
}
