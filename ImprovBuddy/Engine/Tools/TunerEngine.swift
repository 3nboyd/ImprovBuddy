import Combine
import Foundation

@MainActor
final class TunerEngine: ObservableObject {
    @Published private(set) var noteName: String = "-"
    @Published private(set) var midiNote: Int?
    @Published private(set) var cents: Double = 0
    @Published private(set) var confidence: Double = 0
    @Published private(set) var isStable = false

    private var cancellables = Set<AnyCancellable>()
    private var centsWindow: [Double] = []
    private var lockedMidiNote: Int?
    private let settingsStore: ToolsSettingsStore

    init(eventBus: UnifiedEventBus, settingsStore: ToolsSettingsStore) {
        self.settingsStore = settingsStore

        eventBus.pitchPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.updateFromPitch(event)
            }
            .store(in: &cancellables)
    }

    private func updateFromPitch(_ event: PitchEvent) {
        let settings = settingsStore.tuner
        let midi = event.midiNote + Self.a4SemitoneOffset(referenceHz: settings.a4Hz)
        guard midi.isFinite else { return }

        confidence = max(0, min(1, event.confidence))
        guard confidence >= settings.confidenceGate else {
            isStable = false
            midiNote = nil
            return
        }

        var candidate = Int(round(midi))
        if let locked = lockedMidiNote, candidate != locked {
            let movement = abs(midi - Double(locked))
            if movement < Self.toneLatchSemitoneMargin(for: settings.toneChangeSensitivity) {
                candidate = locked
            }
        }

        lockedMidiNote = candidate
        midiNote = candidate

        let rawDeviation = (midi - Double(candidate)) * 100
        let relativePitchClass = Chord.normalizePitchClass(candidate - settings.temperamentRootPitchClass)
        let temperamentOffset = Self.temperamentOffset(
            temperament: settings.temperament,
            relativePitchClass: relativePitchClass
        )

        centsWindow.append(rawDeviation - temperamentOffset)
        if centsWindow.count > 7 {
            centsWindow.removeFirst(centsWindow.count - 7)
        }

        cents = TempoAnalyzer.median(centsWindow)
        isStable = confidence >= settings.confidenceGate && abs(cents) <= 20

        let safeIndex = Chord.normalizePitchClass(candidate)
        noteName = Self.noteNames[safeIndex]
    }

    static let noteNames = [
        "C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"
    ]

    nonisolated static func toneLatchSemitoneMargin(for sensitivity: Double) -> Double {
        let clamped = max(0, min(1, sensitivity))
        return 0.45 - (0.35 * clamped)
    }

    nonisolated static func a4SemitoneOffset(referenceHz: Double) -> Double {
        guard referenceHz > 0 else { return 0 }
        return 12 * log2(440.0 / referenceHz)
    }

    nonisolated static func temperamentOffset(
        temperament: TunerTemperament,
        relativePitchClass: Int
    ) -> Double {
        switch temperament {
        case .equal:
            return 0
        case .just:
            return justOffsets[relativePitchClass] ?? 0
        case .pythagorean:
            return pythagoreanOffsets[relativePitchClass] ?? 0
        }
    }

    private nonisolated static let justOffsets: [Int: Double] = [
        0: 0.0,
        1: 11.73,
        2: 3.91,
        3: 15.64,
        4: -13.69,
        5: -1.96,
        6: -17.49,
        7: 1.96,
        8: 13.69,
        9: -15.64,
        10: -3.91,
        11: -11.73
    ]

    private nonisolated static let pythagoreanOffsets: [Int: Double] = [
        0: 0.0,
        1: -9.78,
        2: 3.91,
        3: -5.87,
        4: 7.82,
        5: -1.96,
        6: 11.73,
        7: 1.96,
        8: -7.82,
        9: 5.87,
        10: -3.91,
        11: 9.78
    ]
}
