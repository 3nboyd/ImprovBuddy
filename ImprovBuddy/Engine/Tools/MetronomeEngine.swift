import AVFoundation
import Foundation
import UIKit

enum MetronomeSubdivision: Int, CaseIterable, Identifiable {
    case quarter = 1
    case eighth = 2
    case triplet = 3
    case sixteenth = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .quarter: "1/4"
        case .eighth: "1/8"
        case .triplet: "Triplet"
        case .sixteenth: "1/16"
        }
    }
}

enum MetronomeSoundSet: String, CaseIterable, Identifiable {
    case woodblock
    case hihat
    case rim

    var id: String { rawValue }

    var baseFrequency: Double {
        switch self {
        case .woodblock: 1200
        case .hihat: 2100
        case .rim: 900
        }
    }
}

@MainActor
final class MetronomeEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var currentStep = 0

    var bpm: Double = 120
    var beatsPerBar: Int = 4
    var subdivision: MetronomeSubdivision = .quarter
    var accentDownbeat = true
    var swingMode = false
    var dropoutProbability: Double = 0
    var soundSet: MetronomeSoundSet = .woodblock
    var hapticsEnabled = false

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var timer: DispatchSourceTimer?

    private var strongClickBuffer: AVAudioPCMBuffer?
    private var weakClickBuffer: AVAudioPCMBuffer?

    init() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)
        configureBuffers(sampleRate: 44_100)
    }

    func start() {
        guard !isRunning else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if !audioEngine.isRunning {
                try audioEngine.start()
            }
        } catch {
            print("Metronome audio start error: \(error)")
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }

        isRunning = true
        currentStep = 0
        scheduleTimer()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        playerNode.stop()
        audioEngine.stop()
        isRunning = false
        currentStep = 0
    }

    func refreshSoundSet() {
        configureBuffers(sampleRate: 44_100)
    }

    private func scheduleTimer() {
        timer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        let interval = 60.0 / bpm / Double(subdivision.rawValue)

        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(2))

        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.tick()
        }

        timer.resume()
        self.timer = timer
    }

    private func tick() {
        guard isRunning else { return }

        let shouldDrop = Double.random(in: 0...1) < dropoutProbability
        if !shouldDrop {
            let stepInBar = currentStep % (beatsPerBar * subdivision.rawValue)
            let isDownbeatStep = stepInBar == 0
            let isPrimaryBeat = stepInBar % subdivision.rawValue == 0
            let useAccent = accentDownbeat && isDownbeatStep

            if swingMode && subdivision == .eighth {
                playSwingClick(stepInBar: stepInBar)
            } else if isPrimaryBeat {
                scheduleClick(accented: useAccent)
            } else {
                scheduleClick(accented: false)
            }

            if hapticsEnabled && isPrimaryBeat {
                Task { @MainActor in
                    let generator = UIImpactFeedbackGenerator(style: isDownbeatStep ? .medium : .light)
                    generator.impactOccurred()
                }
            }
        }

        Task { @MainActor [weak self] in
            self?.currentStep += 1
        }
    }

    private func playSwingClick(stepInBar: Int) {
        let subdivisionSteps = subdivision.rawValue
        let beatStep = stepInBar % subdivisionSteps

        if beatStep == 0 {
            scheduleClick(accented: stepInBar == 0)
        } else {
            scheduleClick(accented: false)
        }
    }

    private func scheduleClick(accented: Bool) {
        guard let buffer = accented ? strongClickBuffer : weakClickBuffer else { return }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func configureBuffers(sampleRate: Double) {
        strongClickBuffer = makeClickBuffer(
            sampleRate: sampleRate,
            frequency: soundSet.baseFrequency + 300,
            amplitude: 0.8
        )

        weakClickBuffer = makeClickBuffer(
            sampleRate: sampleRate,
            frequency: soundSet.baseFrequency,
            amplitude: 0.4
        )
    }

    private func makeClickBuffer(sampleRate: Double, frequency: Double, amplitude: Double) -> AVAudioPCMBuffer? {
        let frameCount = 1_200
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        let twoPiF = 2.0 * Double.pi * frequency
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let envelope = exp(-18.0 * t)
            let sample = sin(twoPiF * t) * envelope * amplitude
            buffer.floatChannelData?.pointee[i] = Float(sample)
        }

        return buffer
    }
}
