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
