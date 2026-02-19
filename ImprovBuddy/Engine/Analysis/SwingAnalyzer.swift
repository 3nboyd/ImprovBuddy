import Foundation

struct SwingSnapshot {
    var ratio: Double
    var consistencyStdDev: Double
}

final class SwingAnalyzer {
    private let targetBPM: Double
    private var onsetTimes: [TimeInterval] = []
    private var ratios: [Double] = []
    private var ratioEMA: Double = 2.0

    init(targetBPM: Double) {
        self.targetBPM = targetBPM
    }

    func reset() {
        onsetTimes.removeAll(keepingCapacity: true)
        ratios.removeAll(keepingCapacity: true)
        ratioEMA = 2.0
    }

    func processOnset(time: TimeInterval) -> SwingSnapshot? {
        onsetTimes.append(time)
        guard onsetTimes.count >= 3 else { return nil }

        let a = onsetTimes[onsetTimes.count - 3]
        let b = onsetTimes[onsetTimes.count - 2]
        let c = onsetTimes[onsetTimes.count - 1]

        let ioi1 = b - a
        let ioi2 = c - b
        let pairDuration = ioi1 + ioi2
        let beatDuration = 60 / targetBPM

        guard beatDuration > 0 else { return nil }
        guard pairDuration > beatDuration * 0.6 && pairDuration < beatDuration * 1.4 else {
            return currentSnapshot()
        }

        guard ioi2 > 0.001 else { return currentSnapshot() }

        let rawRatio = ioi1 / ioi2
        guard rawRatio > 0.6 && rawRatio < 4.5 else { return currentSnapshot() }

        ratioEMA = 0.25 * rawRatio + 0.75 * ratioEMA
        ratios.append(ratioEMA)

        return currentSnapshot()
    }

    func summaryStats() -> SwingStats {
        let avg = ratios.isEmpty ? ratioEMA : ratios.reduce(0, +) / Double(ratios.count)
        let stdDev = std(ratios)
        return SwingStats(averageRatio: avg, consistencyStdDev: stdDev)
    }

    private func currentSnapshot() -> SwingSnapshot {
        SwingSnapshot(ratio: ratioEMA, consistencyStdDev: std(Array(ratios.suffix(32))))
    }

    private func std(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }
}
