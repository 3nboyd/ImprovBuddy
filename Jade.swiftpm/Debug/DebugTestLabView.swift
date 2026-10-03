import SwiftUI

#if DEBUG
struct DebugTestLabView: View {
    @State private var logs: [String] = []
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 14) {
            Button(isRunning ? "Running..." : "Run DSP Validation") {
                runTests()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)

            List(logs, id: \.self) { log in
                Text(log)
                    .font(.system(.footnote, design: .monospaced))
            }
        }
        .padding()
        .navigationTitle("Debug Test Lab")
    }

    private func runTests() {
        isRunning = true
        logs.removeAll(keepingCapacity: true)

        Task.detached(priority: .userInitiated) {
            let pitchLogs = Self.runPitchValidation()
            let onsetLogs = Self.runOnsetAndBPMValidation()

            await MainActor.run {
                logs.append(contentsOf: pitchLogs)
                logs.append(contentsOf: onsetLogs)
                isRunning = false
            }
        }
    }

    nonisolated private static func runPitchValidation() -> [String] {
        let sampleRate = 44_100.0
        let detector = PitchDetector(sampleRate: sampleRate)
        let testMIDINotes = [57, 60, 64, 69]

        var errors: [Double] = []

        for midi in testMIDINotes {
            let frequency = 440.0 * pow(2, Double(midi - 69) / 12)
            let buffer = SignalFactory.sineWave(frequency: frequency, sampleRate: sampleRate, duration: 0.25)

            let frameSize = 2048
            var localEstimates: [Double] = []
            var offset = 0

            while offset + frameSize < buffer.count {
                let frame = Array(buffer[offset..<(offset + frameSize)])
                if let estimate = detector.estimatePitch(frame: frame), estimate.confidence > 0.5 {
                    localEstimates.append(estimate.midiNote)
                }
                offset += 512
            }

            if !localEstimates.isEmpty {
                let median = TempoAnalyzer.median(localEstimates)
                errors.append(abs(median - Double(midi)))
            }
        }

        let meanError = errors.isEmpty ? 999 : errors.reduce(0, +) / Double(errors.count)
        return ["Pitch mean abs midi error: \(String(format: "%.3f", meanError))"]
    }

    nonisolated private static func runOnsetAndBPMValidation() -> [String] {
        let sampleRate = 44_100.0
        let bpm = 120.0
        let signal = SignalFactory.clickTrack(bpm: bpm, sampleRate: sampleRate, duration: 8)

        let onsetDetector = OnsetDetector(refractoryPeriod: 0.08)
        let tempoAnalyzer = TempoAnalyzer(targetBPM: bpm, subdivision: .beat)

        let frameSize = 1024
        var offset = 0
        var onsetCount = 0

        while offset + frameSize < signal.count {
            let frame = Array(signal[offset..<(offset + frameSize)])
            let time = Double(offset) / sampleRate

            let result = onsetDetector.process(frame: frame, time: time)
            if result.isOnset {
                onsetCount += 1
                _ = tempoAnalyzer.processOnset(time: time)
            }

            offset += frameSize
        }

        let tempoSummary = tempoAnalyzer.summaryStats()

        return [
            "Onset detections: \(onsetCount)",
            "BPM test mean abs timing error: \(String(format: "%.2f", tempoSummary.meanAbsoluteErrorMs)) ms",
            "BPM drift slope: \(String(format: "%.4f", tempoSummary.driftSlope))"
        ]
    }
}

private enum SignalFactory {
    static func sineWave(frequency: Double, sampleRate: Double, duration: Double) -> [Float] {
        let count = Int(duration * sampleRate)
        return (0..<count).map { idx in
            let t = Double(idx) / sampleRate
            return Float(sin(2 * .pi * frequency * t) * 0.45)
        }
    }

    static func clickTrack(bpm: Double, sampleRate: Double, duration: Double) -> [Float] {
        let count = Int(duration * sampleRate)
        var signal = Array(repeating: Float.zero, count: count)
        let beatSamples = Int((60 / bpm) * sampleRate)

        var position = 0
        while position < count {
            for i in 0..<120 where position + i < count {
                let envelope = exp(-Double(i) / 25)
                signal[position + i] += Float(envelope)
            }
            position += beatSamples
        }

        return signal
    }
}
#else
struct DebugTestLabView: View {
    var body: some View {
        Text("Debug Test Lab is only available in debug builds.")
            .padding()
    }
}
#endif
