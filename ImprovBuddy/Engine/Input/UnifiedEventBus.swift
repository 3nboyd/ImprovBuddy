import Combine
import Foundation

final class UnifiedEventBus {
    let onsetPublisher = PassthroughSubject<OnsetEvent, Never>()
    let pitchPublisher = PassthroughSubject<PitchEvent, Never>()

    private let lock = NSLock()
    private(set) var onsets: [OnsetEvent] = []
    private(set) var pitches: [PitchEvent] = []

    func publish(onset: OnsetEvent) {
        lock.lock()
        onsets.append(onset)
        lock.unlock()
        onsetPublisher.send(onset)
    }

    func publish(pitch: PitchEvent) {
        lock.lock()
        pitches.append(pitch)
        lock.unlock()
        pitchPublisher.send(pitch)
    }

    func reset() {
        lock.lock()
        onsets.removeAll(keepingCapacity: true)
        pitches.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
