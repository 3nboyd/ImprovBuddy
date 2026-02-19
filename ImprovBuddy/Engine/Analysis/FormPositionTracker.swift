import Foundation

struct FormPosition {
    var measureIndex: Int
    var chorusIndex: Int
    var progressInMeasure: Double
    var sectionLabel: String?
}

final class FormPositionTracker {
    private(set) var measures: [Measure]
    private let timeSignatureTop: Int
    private let targetBPM: Double

    private var alignmentOffset: TimeInterval = 0

    init(measures: [Measure], timeSignatureTop: Int, targetBPM: Double) {
        self.measures = measures.sorted { $0.index < $1.index }
        self.timeSignatureTop = max(1, timeSignatureTop)
        self.targetBPM = max(20, targetBPM)
    }

    func resetAlignment() {
        alignmentOffset = 0
    }

    func jumpToBar(_ barNumber: Int, at elapsed: TimeInterval) {
        guard !measures.isEmpty else { return }
        let barIndex = max(0, min(barNumber - 1, measures.count - 1))
        alignmentOffset = elapsed - (Double(barIndex) * secondsPerMeasure)
    }

    func restartChorus(at elapsed: TimeInterval) {
        alignmentOffset = elapsed
    }

    func currentPosition(at elapsed: TimeInterval) -> FormPosition {
        guard !measures.isEmpty else {
            return FormPosition(measureIndex: 0, chorusIndex: 0, progressInMeasure: 0, sectionLabel: nil)
        }

        let normalizedElapsed = max(0, elapsed - alignmentOffset)
        let totalMeasuresElapsed = Int(floor(normalizedElapsed / secondsPerMeasure))
        let measureIndex = positiveMod(totalMeasuresElapsed, measures.count)
        let chorus = totalMeasuresElapsed / measures.count
        let measureStart = Double(totalMeasuresElapsed) * secondsPerMeasure
        let progress = min(1, max(0, (normalizedElapsed - measureStart) / secondsPerMeasure))

        return FormPosition(
            measureIndex: measureIndex,
            chorusIndex: chorus,
            progressInMeasure: progress,
            sectionLabel: measures[measureIndex].sectionLabel
        )
    }

    func currentMeasure(at elapsed: TimeInterval) -> Measure? {
        guard !measures.isEmpty else { return nil }
        let position = currentPosition(at: elapsed)
        return measures[position.measureIndex]
    }

    func nearestStrongBeatTime(for elapsed: TimeInterval) -> TimeInterval {
        let beatDuration = 60 / targetBPM
        let beatsPerMeasure = Double(timeSignatureTop)
        let normalizedElapsed = max(0, elapsed - alignmentOffset)

        let measureNumber = floor(normalizedElapsed / secondsPerMeasure)
        let measureStart = measureNumber * secondsPerMeasure

        let beatOffsets = [0.0, 2.0].filter { $0 < beatsPerMeasure }
        let strongBeatTimes = beatOffsets.map { measureStart + ($0 * beatDuration) }

        let nearest = strongBeatTimes.min(by: { abs($0 - normalizedElapsed) < abs($1 - normalizedElapsed) }) ?? measureStart
        return nearest + alignmentOffset
    }

    private var secondsPerMeasure: TimeInterval {
        let beatDuration = 60 / targetBPM
        return Double(timeSignatureTop) * beatDuration
    }

    private func positiveMod(_ lhs: Int, _ rhs: Int) -> Int {
        let mod = lhs % rhs
        return mod >= 0 ? mod : mod + rhs
    }
}
