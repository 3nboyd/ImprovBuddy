import AVFoundation
import Foundation
import os

final class SimpleSynth: ObservableObject {
    private struct RenderState {
        var sampleRate: Double = 44_100
        var phase: Double = 0
        var currentFrequency: Double = 0
        var amplitude: Double = 0
    }

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let stateLock = OSAllocatedUnfairLock(initialState: RenderState())

    init() {
        setupEngine()
    }

    func playMIDINotes(_ notes: [Int], noteDuration: Double = 0.2) {
        let lock = stateLock
        let frequencies = notes.map { 440 * pow(2, Double($0 - 69) / 12) }
        for (index, frequency) in frequencies.enumerated() {
            let delay = Double(index) * noteDuration
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                lock.withLock { state in
                    state.currentFrequency = frequency
                    state.amplitude = 0.18
                }
            }
        }

        let stopDelay = Double(notes.count) * noteDuration
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + stopDelay) {
            lock.withLock { state in
                state.amplitude = 0
            }
        }
    }

    func play(frequency: Double, amplitude: Double) {
        stateLock.withLock { state in
            state.currentFrequency = frequency
            state.amplitude = amplitude
        }
    }

    func stopTone() {
        stateLock.withLock { state in
            state.amplitude = 0
        }
    }

    private func setupEngine() {
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        stateLock.withLock { state in
            state.sampleRate = outputFormat.sampleRate
        }

        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }

            let bufferCount = Int(audioBufferList.pointee.mNumberBuffers)
            let audioBuffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let initialState = self.stateLock.withLock { $0 }
            var phase = initialState.phase
            let frequency = initialState.currentFrequency
            let amplitude = initialState.amplitude
            let sampleRate = max(1, initialState.sampleRate)

            for frame in 0..<Int(frameCount) {
                let value = Float(sin(phase) * amplitude)
                phase += 2.0 * Double.pi * frequency / sampleRate
                if phase > 2.0 * Double.pi {
                    phase -= 2.0 * Double.pi
                }

                for bufferIndex in 0..<bufferCount {
                    let pointer = audioBuffers[bufferIndex].mData?.assumingMemoryBound(to: Float.self)
                    pointer?[frame] = value
                }
            }

            let updatedPhase = phase
            self.stateLock.withLock { state in
                state.phase = updatedPhase
            }

            return noErr
        }

        if let sourceNode {
            engine.attach(sourceNode)
            engine.connect(sourceNode, to: engine.mainMixerNode, format: outputFormat)
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
    }
}
