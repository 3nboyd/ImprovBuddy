import Accelerate
import Foundation

final class OnsetDetector {
    private var previousFrame: [Float] = []
    private var fluxHistory: [Float] = []
    private var lastOnsetTime: TimeInterval = -10

    private let historySize = 32
    private let refractoryPeriod: TimeInterval

    init(refractoryPeriod: TimeInterval = 0.06) {
        self.refractoryPeriod = refractoryPeriod
    }

    func reset() {
        previousFrame.removeAll(keepingCapacity: true)
        fluxHistory.removeAll(keepingCapacity: true)
        lastOnsetTime = -10
    }

    func process(frame: [Float], time: TimeInterval) -> (isOnset: Bool, confidence: Double) {
        guard !frame.isEmpty else { return (false, 0) }

        let energy = rms(frame)
        let prevEnergy = previousFrame.isEmpty ? energy : rms(previousFrame)
        var flux = max(0, energy - prevEnergy)

        if frame.count == previousFrame.count, !previousFrame.isEmpty {
            var diff = [Float](repeating: 0, count: frame.count)
            vDSP_vsub(previousFrame, 1, frame, 1, &diff, 1, vDSP_Length(frame.count))
            var absDiff = [Float](repeating: 0, count: frame.count)
            vDSP_vabs(diff, 1, &absDiff, 1, vDSP_Length(frame.count))
            var mean: Float = 0
            vDSP_meanv(absDiff, 1, &mean, vDSP_Length(absDiff.count))
            flux += mean * 0.6
        }

        previousFrame = frame
        fluxHistory.append(flux)
        if fluxHistory.count > historySize {
            fluxHistory.removeFirst(fluxHistory.count - historySize)
        }

        guard fluxHistory.count >= 8 else {
            return (false, 0)
        }

        let baseline = fluxHistory.reduce(Float.zero, +) / Float(fluxHistory.count)
        let threshold = baseline * 1.7 + 0.001

        guard flux > threshold else {
            return (false, 0)
        }

        guard time - lastOnsetTime >= refractoryPeriod else {
            return (false, 0)
        }

        lastOnsetTime = time
        let confidence = min(1.0, Double((flux - threshold) / max(threshold, 0.0001)))
        return (true, max(0.1, confidence))
    }

    private func rms(_ frame: [Float]) -> Float {
        var value: Float = 0
        vDSP_rmsqv(frame, 1, &value, vDSP_Length(frame.count))
        return value
    }
}
