import Foundation

struct PitchEstimate {
    var frequency: Double
    var midiNote: Double
    var confidence: Double
}

final class PitchDetector {
    private let sampleRate: Double
    private let minFrequency: Double
    private let maxFrequency: Double
    private let threshold: Double
    private var recentMidi: [Double] = []

    init(sampleRate: Double, minFrequency: Double = 65, maxFrequency: Double = 1200, threshold: Double = 0.15) {
        self.sampleRate = sampleRate
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        self.threshold = threshold
    }

    func reset() {
        recentMidi.removeAll(keepingCapacity: true)
    }

    func estimatePitch(frame: [Float]) -> PitchEstimate? {
        guard frame.count > 1024 else { return nil }
        let amplitude = rms(frame)
        guard amplitude > 0.005 else { return nil }

        let minLag = max(2, Int(sampleRate / maxFrequency))
        let maxLag = min(frame.count / 2, Int(sampleRate / minFrequency))
        guard maxLag > minLag + 2 else { return nil }

        var difference = Array(repeating: Double.zero, count: maxLag + 1)
        for tau in minLag...maxLag {
            var sum = 0.0
            let upper = frame.count - tau
            for i in 0..<upper {
                let delta = Double(frame[i] - frame[i + tau])
                sum += delta * delta
            }
            difference[tau] = sum
        }

        var cmnd = Array(repeating: Double(1), count: maxLag + 1)
        var running = 0.0
        for tau in minLag...maxLag {
            running += difference[tau]
            if running > 0 {
                cmnd[tau] = difference[tau] * Double(tau - minLag + 1) / running
            }
        }

        var candidateTau: Int?
        var tau = minLag
        while tau <= maxLag {
            if cmnd[tau] < threshold {
                candidateTau = tau
                while tau + 1 <= maxLag && cmnd[tau + 1] < cmnd[tau] {
                    tau += 1
                    candidateTau = tau
                }
                break
            }
            tau += 1
        }

        if candidateTau == nil,
           let minValue = cmnd[minLag...maxLag].min(),
           let minIndex = cmnd.firstIndex(of: minValue) {
            candidateTau = minIndex
        }

        guard let finalTau = candidateTau, finalTau > 0 else { return nil }

        let refinedTau = parabolicRefine(cmnd: cmnd, at: finalTau)
        let frequency = sampleRate / refinedTau
        guard frequency.isFinite, frequency > 0 else { return nil }

        let midi = 69 + 12 * log2(frequency / 440)
        let confidence = max(0, min(1, 1 - cmnd[finalTau]))

        recentMidi.append(midi)
        if recentMidi.count > 5 {
            recentMidi.removeFirst(recentMidi.count - 5)
        }

        let smoothedMidi = TempoAnalyzer.median(recentMidi)

        return PitchEstimate(
            frequency: frequency,
            midiNote: smoothedMidi,
            confidence: confidence
        )
    }

    private func rms(_ frame: [Float]) -> Double {
        var sum = 0.0
        for sample in frame {
            let value = Double(sample)
            sum += value * value
        }
        return sqrt(sum / Double(frame.count))
    }

    private func parabolicRefine(cmnd: [Double], at index: Int) -> Double {
        let left = max(index - 1, 0)
        let right = min(index + 1, cmnd.count - 1)

        guard left != index, right != index else {
            return Double(index)
        }

        let alpha = cmnd[left]
        let beta = cmnd[index]
        let gamma = cmnd[right]
        let denominator = alpha - 2 * beta + gamma

        guard abs(denominator) > 0.000001 else {
            return Double(index)
        }

        let correction = 0.5 * (alpha - gamma) / denominator
        return Double(index) + correction
    }
}
