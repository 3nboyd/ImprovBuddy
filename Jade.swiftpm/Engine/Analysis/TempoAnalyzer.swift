import Foundation

enum GridSubdivision: Int, Codable, CaseIterable, Identifiable {
    case beat = 1
    case eighth = 2
    case triplet = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .beat: "Beat"
        case .eighth: "Eighth"
        case .triplet: "Triplet"
        }
    }
}

struct TempoSnapshot {
    var liveBPM: Double
    var latestErrorMs: Double
    var medianErrorMs: Double
    var signedBiasMs: Double
    var stability: Double
    var driftSlope: Double
    var isDrifting: Bool
}

final class TempoAnalyzer {
    private let targetBPM: Double
    private let subdivision: GridSubdivision

    private var onsetTimes: [TimeInterval] = []
    private var timingErrorsMs: [Double] = []
    private var bpmEMA: Double

    init(targetBPM: Double, subdivision: GridSubdivision = .eighth) {
        self.targetBPM = targetBPM
        self.subdivision = subdivision
        self.bpmEMA = targetBPM
    }

    func reset() {
        onsetTimes.removeAll(keepingCapacity: true)
        timingErrorsMs.removeAll(keepingCapacity: true)
        bpmEMA = targetBPM
    }

    func processOnset(time: TimeInterval) -> TempoSnapshot {
        onsetTimes.append(time)

        let errorMs = nearestGridErrorMs(for: time)
        timingErrorsMs.append(errorMs)

        updateLiveBPM()

        let recentErrors = timingErrorsMs.suffix(32)
        let absErrors = recentErrors.map { abs($0) }
        let medianError = Self.median(absErrors)
        let signedBias = recentErrors.isEmpty ? 0 : recentErrors.reduce(0, +) / Double(recentErrors.count)
        let driftSlope = computeDriftSlope()
        let stability = max(0, 1 - (medianError / 60))
        let isDrifting = medianError > 20 || abs(driftSlope) > 0.15 || abs(bpmEMA - targetBPM) > 2.0

        return TempoSnapshot(
            liveBPM: bpmEMA,
            latestErrorMs: errorMs,
            medianErrorMs: medianError,
            signedBiasMs: signedBias,
            stability: stability,
            driftSlope: driftSlope,
            isDrifting: isDrifting
        )
    }

    func summaryStats() -> TempoDriftStats {
        let absErrors = timingErrorsMs.map { abs($0) }
        let meanAbsolute = absErrors.isEmpty ? 0 : absErrors.reduce(0, +) / Double(absErrors.count)
        let signedBias = timingErrorsMs.isEmpty ? 0 : timingErrorsMs.reduce(0, +) / Double(timingErrorsMs.count)
        return TempoDriftStats(
            meanAbsoluteErrorMs: meanAbsolute,
            signedBiasMs: signedBias,
            driftSlope: computeDriftSlope(),
            stabilityScore: max(0, 1 - (meanAbsolute / 60))
        )
    }

    func allTimingErrors() -> [Double] { timingErrorsMs }

    private func nearestGridErrorMs(for onsetTime: TimeInterval) -> Double {
        let beatDuration = 60.0 / targetBPM
        let gridDuration: TimeInterval = beatDuration / Double(subdivision.rawValue)
        guard gridDuration > 0 else { return 0 }

        let nearestIndex = round(onsetTime / gridDuration)
        let nearestGridTime = nearestIndex * gridDuration
        return (onsetTime - nearestGridTime) * 1000
    }

    private func updateLiveBPM() {
        let recentOnsets = onsetTimes.suffix(8)
        guard recentOnsets.count >= 3 else { return }

        var iois: [Double] = []
        for pair in zip(recentOnsets, recentOnsets.dropFirst()) {
            let ioi = pair.1 - pair.0
            if ioi > 0.05 && ioi < 2.0 {
                iois.append(ioi)
            }
        }

        guard !iois.isEmpty else { return }
        let ioiMedian = Self.median(iois)
        guard ioiMedian > 0 else { return }

        let rawBPM = 60 / ioiMedian
        bpmEMA = (0.2 * rawBPM) + (0.8 * bpmEMA)
    }

    private func computeDriftSlope() -> Double {
        let errors = timingErrorsMs.suffix(24)
        guard errors.count > 3 else { return 0 }

        let values = Array(errors)
        let x = values.indices.map(Double.init)
        let xMean = x.reduce(0, +) / Double(x.count)
        let yMean = values.reduce(0, +) / Double(values.count)

        var numerator = 0.0
        var denominator = 0.0

        for idx in values.indices {
            let dx = x[idx] - xMean
            let dy = values[idx] - yMean
            numerator += dx * dy
            denominator += dx * dx
        }

        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
