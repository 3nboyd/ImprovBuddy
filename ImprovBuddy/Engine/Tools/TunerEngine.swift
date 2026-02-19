import Combine
import Foundation

@MainActor
final class TunerEngine: ObservableObject {
    @Published private(set) var noteName: String = "-"
    @Published private(set) var cents: Double = 0
    @Published private(set) var confidence: Double = 0
    @Published var a4ReferenceHz: Double = 440

    private var cancellables = Set<AnyCancellable>()
    private var centsWindow: [Double] = []

    init(eventBus: UnifiedEventBus) {
        eventBus.pitchPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.updateFromPitch(event)
            }
            .store(in: &cancellables)
    }

    private func updateFromPitch(_ event: PitchEvent) {
        let midi = event.midiNote
        guard midi.isFinite else { return }

        let rounded = round(midi)
        let deviation = (midi - rounded) * 100

        centsWindow.append(deviation)
        if centsWindow.count > 5 {
            centsWindow.removeFirst(centsWindow.count - 5)
        }

        cents = TempoAnalyzer.median(centsWindow)
        confidence = event.confidence

        let index = Int(rounded) % 12
        let safeIndex = index >= 0 ? index : index + 12
        noteName = Self.noteNames[safeIndex]
    }

    static let noteNames = [
        "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"
    ]
}
