import Combine
import Foundation

enum ToolOverlayKind: String, Codable, CaseIterable, Identifiable {
    case tuner
    case bpm

    var id: String { rawValue }
}

enum OverlayCorner: String, Codable, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case middleLeft
    case middleRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }
}

struct ToolOverlayPreferences: Codable, Hashable {
    var corner: OverlayCorner
    var offsetX: Double
    var offsetY: Double
    var isExpanded: Bool
    var isVisible: Bool

    static let tunerDefault = ToolOverlayPreferences(
        corner: .topLeft,
        offsetX: 0,
        offsetY: 0,
        isExpanded: false,
        isVisible: true
    )

    static let bpmDefault = ToolOverlayPreferences(
        corner: .topRight,
        offsetX: 0,
        offsetY: 0,
        isExpanded: false,
        isVisible: true
    )
}

@MainActor
final class ToolOverlayPreferencesStore: ObservableObject {
    @Published var tuner: ToolOverlayPreferences {
        didSet { persist(tuner, key: Keys.tuner) }
    }

    @Published var bpm: ToolOverlayPreferences {
        didSet { persist(bpm, key: Keys.bpm) }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()

    private enum Keys {
        static let tuner = "tool.overlay.preferences.tuner.v1"
        static let bpm = "tool.overlay.preferences.bpm.v1"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedTuner: ToolOverlayPreferences? = Self.load(defaults: defaults, key: Keys.tuner)
        let loadedBPM: ToolOverlayPreferences? = Self.load(defaults: defaults, key: Keys.bpm)

        self.tuner = loadedTuner ?? .tunerDefault
        self.bpm = loadedBPM ?? .bpmDefault

        // Migrate users who never customized overlays from legacy defaults:
        // old tuner=topRight, old bpm=bottomLeft.
        if loadedTuner == .legacyTunerDefault, loadedBPM == .legacyBPMDefault {
            self.tuner = .tunerDefault
            self.bpm = .bpmDefault
        }
    }

    func reset() {
        tuner = .tunerDefault
        bpm = .bpmDefault
    }

    private static func load<T: Decodable>(defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

private extension ToolOverlayPreferences {
    static let legacyTunerDefault = ToolOverlayPreferences(
        corner: .topRight,
        offsetX: 0,
        offsetY: 0,
        isExpanded: false,
        isVisible: true
    )

    static let legacyBPMDefault = ToolOverlayPreferences(
        corner: .bottomLeft,
        offsetX: 0,
        offsetY: 0,
        isExpanded: false,
        isVisible: true
    )
}

@MainActor
final class ServiceContainer: ObservableObject {
    let eventBus = UnifiedEventBus()

    let toolsSettings = ToolsSettingsStore()
    let toolOverlayPreferences = ToolOverlayPreferencesStore()
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
            toolOverlayPreferences.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
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

    func acquireOverlayMicrophoneLease() async -> AudioUsageCoordinator.LeaseToken? {
        await audioUsageCoordinator.acquireMicrophone(recordAudio: false)
    }

    func releaseOverlayLease(_ token: AudioUsageCoordinator.LeaseToken?) {
        audioUsageCoordinator.release(token)
    }
}
