@preconcurrency import AVFoundation
import Foundation
import UIKit
import os

enum GrooveVoice: String, CaseIterable, Hashable {
    case kick
    case snare
    case hihat
}

struct GrooveEvent: Hashable {
    var step: Int
    var voice: GrooveVoice
    var accent: Double
}

struct GroovePattern {
    var meter: MeterSignature
    var subdivision: MetronomeSubdivision
    var events: [GrooveEvent]

    var stepsPerBar: Int {
        meter.top * max(1, subdivision.rawValue)
    }

    func events(at step: Int) -> [GrooveEvent] {
        events.filter { $0.step == step }
    }
}

struct GroovePatternGenerator {
    func generate(
        style: GrooveStyle,
        meter: MeterSignature,
        subdivision: MetronomeSubdivision,
        intensity: Double
    ) -> GroovePattern {
        let stepsPerBeat = max(1, subdivision.rawValue)
        let beats = max(1, meter.top)
        let totalSteps = beats * stepsPerBeat
        if meter.top == 4, meter.bottom == 4 {
            return GroovePattern(
                meter: meter,
                subdivision: subdivision,
                events: dedupe(cannedFourFourPattern(style: style, subdivision: subdivision, intensity: intensity))
            )
        }

        var events: [GrooveEvent] = []

        let groups = grouping(top: beats, bottom: meter.bottom)
        let groupStarts = cumulativeStarts(groups)
        let groupStartSet = Set(groupStarts)

        for beat in 0..<beats {
            let beatStep = beat * stepsPerBeat
            let primaryAccent = beat == 0 ? 1.0 : (groupStartSet.contains(beat) ? 0.82 : 0.72)

            events.append(GrooveEvent(step: beatStep, voice: .hihat, accent: 0.68 + 0.2 * intensity))

            if stepsPerBeat >= 2 {
                let offbeat = beatStep + 1
                if offbeat < totalSteps {
                    events.append(GrooveEvent(step: offbeat, voice: .hihat, accent: 0.4 + 0.22 * intensity))
                }
            }

            if stepsPerBeat >= 3 {
                let tertiary = beatStep + (stepsPerBeat - 1)
                if tertiary < totalSteps {
                    events.append(GrooveEvent(step: tertiary, voice: .hihat, accent: 0.35 + 0.2 * intensity))
                }
            }

            switch style {
            case .rock:
                if beat == 0 || beat == beats - 1 || groupStartSet.contains(beat) {
                    events.append(GrooveEvent(step: beatStep, voice: .kick, accent: primaryAccent))
                }
                if isBackbeat(beat: beat, totalBeats: beats) {
                    events.append(GrooveEvent(step: beatStep, voice: .snare, accent: 0.85))
                }

            case .swing:
                if beat == 0 || groupStartSet.contains(beat) {
                    events.append(GrooveEvent(step: beatStep, voice: .kick, accent: primaryAccent))
                }
                if isBackbeat(beat: beat, totalBeats: beats) || (beats <= 3 && beat == beats - 1) {
                    events.append(GrooveEvent(step: beatStep, voice: .snare, accent: 0.8))
                }
                if stepsPerBeat >= 2 {
                    let longStep = beatStep + max(1, stepsPerBeat - 1)
                    if longStep < totalSteps {
                        events.append(GrooveEvent(step: longStep, voice: .hihat, accent: 0.5 + 0.2 * intensity))
                    }
                }

            case .funk:
                if beat == 0 || groupStartSet.contains(beat) || beat % 2 == 0 {
                    events.append(GrooveEvent(step: beatStep, voice: .kick, accent: primaryAccent))
                }

                if isBackbeat(beat: beat, totalBeats: beats) {
                    events.append(GrooveEvent(step: beatStep, voice: .snare, accent: 0.88))
                }

                if stepsPerBeat >= 2 {
                    let ghostStep = beatStep + 1
                    if ghostStep < totalSteps && beat % 2 == 1 {
                        events.append(GrooveEvent(step: ghostStep, voice: .snare, accent: 0.35 + 0.25 * intensity))
                    }
                }
            }
        }

        return GroovePattern(
            meter: meter,
            subdivision: subdivision,
            events: dedupe(events)
        )
    }

    private func cannedFourFourPattern(
        style: GrooveStyle,
        subdivision: MetronomeSubdivision,
        intensity: Double
    ) -> [GrooveEvent] {
        let stepsPerBeat = max(1, subdivision.rawValue)
        let stepsPerBar = stepsPerBeat * 4
        var events: [GrooveEvent] = []

        func step(_ beatPosition: Double) -> Int {
            let raw = Int(round(beatPosition * Double(stepsPerBeat)))
            return max(0, min(stepsPerBar - 1, raw))
        }

        for beat in 0..<4 {
            let beatStart = beat * stepsPerBeat
            events.append(GrooveEvent(step: beatStart, voice: .hihat, accent: beat == 0 || beat == 2 ? 0.78 : 0.62))
            if stepsPerBeat >= 2 {
                events.append(GrooveEvent(step: min(stepsPerBar - 1, beatStart + stepsPerBeat - 1), voice: .hihat, accent: 0.48 + 0.14 * intensity))
            }
            if stepsPerBeat >= 4 {
                events.append(GrooveEvent(step: min(stepsPerBar - 1, beatStart + 1), voice: .hihat, accent: 0.36 + 0.1 * intensity))
                events.append(GrooveEvent(step: min(stepsPerBar - 1, beatStart + 2), voice: .hihat, accent: 0.4 + 0.12 * intensity))
            }
        }

        switch style {
        case .rock:
            events.append(GrooveEvent(step: step(0.0), voice: .kick, accent: 1.0))
            events.append(GrooveEvent(step: step(1.5), voice: .kick, accent: 0.7))
            events.append(GrooveEvent(step: step(2.0), voice: .kick, accent: 0.86))
            events.append(GrooveEvent(step: step(1.0), voice: .snare, accent: 0.9))
            events.append(GrooveEvent(step: step(3.0), voice: .snare, accent: 0.92))

        case .swing:
            events.append(GrooveEvent(step: step(0.0), voice: .kick, accent: 0.95))
            events.append(GrooveEvent(step: step(2.0), voice: .kick, accent: 0.84))
            events.append(GrooveEvent(step: step(3.5), voice: .kick, accent: 0.66))
            events.append(GrooveEvent(step: step(1.0), voice: .snare, accent: 0.82))
            events.append(GrooveEvent(step: step(3.0), voice: .snare, accent: 0.86))

        case .funk:
            events.append(GrooveEvent(step: step(0.0), voice: .kick, accent: 1.0))
            events.append(GrooveEvent(step: step(0.75), voice: .kick, accent: 0.58 + 0.16 * intensity))
            events.append(GrooveEvent(step: step(1.75), voice: .kick, accent: 0.66 + 0.14 * intensity))
            events.append(GrooveEvent(step: step(2.5), voice: .kick, accent: 0.62 + 0.16 * intensity))
            events.append(GrooveEvent(step: step(1.0), voice: .snare, accent: 0.88))
            events.append(GrooveEvent(step: step(3.0), voice: .snare, accent: 0.94))
            events.append(GrooveEvent(step: step(2.25), voice: .snare, accent: 0.38 + 0.2 * intensity))
            events.append(GrooveEvent(step: step(3.25), voice: .snare, accent: 0.35 + 0.18 * intensity))
        }

        return events
    }

    private func dedupe(_ events: [GrooveEvent]) -> [GrooveEvent] {
        var merged: [Int: [GrooveVoice: Double]] = [:]

        for event in events {
            var voices = merged[event.step, default: [:]]
            voices[event.voice] = max(voices[event.voice] ?? 0, event.accent)
            merged[event.step] = voices
        }

        return merged
            .sorted(by: { $0.key < $1.key })
            .flatMap { step, voices in
                voices.map { voice, accent in
                    GrooveEvent(step: step, voice: voice, accent: accent)
                }
            }
            .sorted {
                if $0.step != $1.step { return $0.step < $1.step }
                return $0.voice.rawValue < $1.voice.rawValue
            }
    }

    private func grouping(top: Int, bottom: Int) -> [Int] {
        let beats = max(1, top)
        if bottom == 8 {
            var remaining = beats
            var groups: [Int] = []

            while remaining > 0 {
                if remaining == 4 {
                    groups.append(2)
                    groups.append(2)
                    break
                }
                if remaining >= 3 && (remaining % 2 == 1 || remaining > 6) {
                    groups.append(3)
                    remaining -= 3
                } else {
                    groups.append(2)
                    remaining -= 2
                }
            }
            return groups
        }

        if beats <= 4 {
            return Array(repeating: 1, count: beats)
        }

        var groups: [Int] = []
        var remaining = beats
        while remaining > 0 {
            let chunk = remaining >= 4 ? 4 : remaining
            groups.append(chunk)
            remaining -= chunk
        }
        return groups
    }

    private func cumulativeStarts(_ groups: [Int]) -> [Int] {
        var starts: [Int] = []
        var running = 0
        for size in groups {
            starts.append(running)
            running += size
        }
        return starts
    }

    private func isBackbeat(beat: Int, totalBeats: Int) -> Bool {
        if totalBeats >= 4 {
            return beat == 1 || beat == 3 || (totalBeats > 4 && beat == totalBeats - 2)
        }
        return beat == max(1, totalBeats - 1)
    }
}

enum MetronomeSubdivision: Int, CaseIterable, Codable, Identifiable {
    case quarter = 1
    case eighth = 2
    case triplet = 3
    case sixteenth = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .quarter: "Quarter"
        case .eighth: "Eighth"
        case .triplet: "Triplet"
        case .sixteenth: "Sixteenth"
        }
    }

    var notationSymbol: String {
        switch self {
        case .quarter: "♩"
        case .eighth: "♪"
        case .triplet: "♪♪♪"
        case .sixteenth: "♬"
        }
    }

    var notationLabel: String {
        switch self {
        case .quarter: "♩ 1/4"
        case .eighth: "♪ 1/8"
        case .triplet: "♪♪♪ 3:2"
        case .sixteenth: "♬ 1/16"
        }
    }
}

enum MetronomeSoundSet: String, CaseIterable, Codable, Identifiable {
    case woodblock
    case hihat
    case rim
    case digital
    case cowbell
    case clave
    case shaker
    case tick
    case sidestick
    case triangle
    case analogPulse
    case beep
    case pip
    case block
    case snap
    case bongo
    case conga
    case cabasa
    case clap

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .woodblock: "Woodblock"
        case .hihat: "Hi-Hat"
        case .rim: "Rim"
        case .digital: "Digital"
        case .cowbell: "Cowbell"
        case .clave: "Clave"
        case .shaker: "Shaker"
        case .tick: "Tick"
        case .sidestick: "Side Stick"
        case .triangle: "Triangle"
        case .analogPulse: "Analog Pulse"
        case .beep: "Beep"
        case .pip: "Pip"
        case .block: "Block"
        case .snap: "Snap"
        case .bongo: "Bongo"
        case .conga: "Conga"
        case .cabasa: "Cabasa"
        case .clap: "Clap"
        }
    }

    var baseFrequency: Double {
        switch self {
        case .woodblock: 1200
        case .hihat: 2100
        case .rim: 900
        case .digital: 1760
        case .cowbell: 820
        case .clave: 1680
        case .shaker: 3500
        case .tick: 2400
        case .sidestick: 1500
        case .triangle: 3100
        case .analogPulse: 1360
        case .beep: 1840
        case .pip: 2460
        case .block: 1320
        case .snap: 1680
        case .bongo: 420
        case .conga: 320
        case .cabasa: 3920
        case .clap: 2150
        }
    }
}

@MainActor
final class MetronomeEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var currentStep = 0
    @Published private(set) var currentBar = 0
    @Published private(set) var isCountInActive = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var beatPulseID = 0

    var bpm: Double = 120
    var meter = MeterSignature(top: 4, bottom: 4)
    var subdivision: MetronomeSubdivision = .quarter
    var countInBars = 1
    var soundSet: MetronomeSoundSet = .woodblock
    var masterVolume: Double = 0.8
    var swingAmount: Double = 0.0
    var grooveEnabled = false
    var grooveStyle: GrooveStyle = .rock
    var grooveIntensity: Double = 0.6
    var humanizeMs: Double = 0
    var hapticsEnabled = false
    var subdivisionUsesAlternateClick = true

    private struct VoiceSpec {
        var frequency: Double
        var amplitude: Double
        var durationSeconds: Double
        var decaySeconds: Double
        var noiseMix: Double
    }

    private struct ActiveVoice {
        var phase: Double
        var frequency: Double
        var amplitude: Double
        var decayPerSample: Double
        var remainingSamples: Int
        var noiseMix: Double
    }

    private struct RenderState {
        var sampleRate: Double = 44_100
        var activeVoices: [ActiveVoice] = []
        var noiseState: UInt64 = 0xA5A5_F00D_1234_5678
    }

    private let audioEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let grooveGenerator = GroovePatternGenerator()
    private let renderStateLock = OSAllocatedUnfairLock(initialState: RenderState())
    private let enableAudioIO: Bool
    private var audioSessionConfigured = false

    private var schedulerTask: Task<Void, Never>?
    private var nextStepTime: TimeInterval = 0
    private var countInStepsRemaining = 0
    private var groovePatternByStep: [Int: [GrooveEvent]] = [:]
    private var tapTimes: [TimeInterval] = []

    init(enableAudioIO: Bool = true) {
        self.enableAudioIO = enableAudioIO
        if enableAudioIO {
            setupAudioGraphIfNeeded()
        }
        refreshPattern()
    }

    func apply(settings: MetronomeSettings) {
        bpm = clamp(settings.bpm, min: 30, max: 320)
        meter = MeterSignature(top: settings.meter.top, bottom: settings.meter.bottom)
        subdivision = settings.subdivision
        countInBars = Int(clamp(Double(settings.countInBars), min: 0, max: 4))
        soundSet = settings.soundSet
        masterVolume = clamp(settings.masterVolume, min: 0, max: 1)
        swingAmount = clamp(settings.swingAmount, min: 0, max: 1)
        grooveEnabled = settings.grooveEnabled
        grooveStyle = settings.grooveStyle
        grooveIntensity = clamp(settings.grooveIntensity, min: 0, max: 1)
        humanizeMs = clamp(settings.humanizeMs, min: 0, max: 25)
        hapticsEnabled = settings.hapticsEnabled
        subdivisionUsesAlternateClick = settings.subdivisionUsesAlternateClick

        refreshSoundSet()
        refreshPattern()

        if isRunning {
            restartSchedulerKeepingPhase()
        }
    }

    func exportSettings() -> MetronomeSettings {
        MetronomeSettings(
            bpm: bpm,
            meter: meter,
            subdivision: subdivision,
            countInBars: countInBars,
            soundSet: soundSet,
            masterVolume: masterVolume,
            swingAmount: swingAmount,
            grooveEnabled: grooveEnabled,
            grooveStyle: grooveStyle,
            grooveIntensity: grooveIntensity,
            humanizeMs: humanizeMs,
            hapticsEnabled: hapticsEnabled,
            subdivisionUsesAlternateClick: subdivisionUsesAlternateClick
        )
    }

    func setBPM(_ value: Double) {
        bpm = clamp(value, min: 30, max: 320)
        if isRunning {
            restartSchedulerKeepingPhase()
        }
    }

    func registerTapTempo() -> Double? {
        let now = ProcessInfo.processInfo.systemUptime
        tapTimes.append(now)
        if tapTimes.count > 8 {
            tapTimes.removeFirst(tapTimes.count - 8)
        }

        let intervals = zip(tapTimes, tapTimes.dropFirst()).map { $1 - $0 }.filter { $0 > 0.08 && $0 < 2.0 }
        guard intervals.count >= 2 else { return nil }

        let newBPM = 60 / TempoAnalyzer.median(intervals)
        setBPM(newBPM)
        return bpm
    }

    func start() {
        guard !isRunning else { return }
        lastErrorMessage = nil

        if enableAudioIO {
            do {
                try configureAudioSessionIfNeeded()
                setupAudioGraphIfNeeded()
                if !audioEngine.isRunning {
                    audioEngine.prepare()
                    try audioEngine.start()
                }
                syncRenderSampleRateFromOutput()
            } catch {
                print("Metronome audio start error: \(error)")
                lastErrorMessage = error.localizedDescription
                return
            }
        }

        currentStep = 0
        currentBar = 0
        beatPulseID = 0
        countInStepsRemaining = countInBars * stepsPerBar
        isCountInActive = countInStepsRemaining > 0

        refreshPattern()

        nextStepTime = ProcessInfo.processInfo.systemUptime + 0.06

        isRunning = true
        scheduleTimer()
    }

    func stop() {
        schedulerTask?.cancel()
        schedulerTask = nil

        isRunning = false
        currentStep = 0
        currentBar = 0
        beatPulseID = 0
        countInStepsRemaining = 0
        isCountInActive = false
        nextStepTime = 0

        renderStateLock.withLock { state in
            state.activeVoices.removeAll(keepingCapacity: true)
        }
    }

    func refreshSoundSet() {
        // Source-node synth mode uses procedural voice specs, no buffer refresh needed.
    }

    func previewPattern() -> GroovePattern {
        grooveGenerator.generate(
            style: grooveStyle,
            meter: meter,
            subdivision: subdivision,
            intensity: grooveIntensity
        )
    }

    private func restartSchedulerKeepingPhase() {
        guard isRunning else { return }
        schedulerTask?.cancel()
        schedulerTask = nil

        nextStepTime = ProcessInfo.processInfo.systemUptime + 0.05
        scheduleTimer()
    }

    private func scheduleTimer() {
        schedulerTask?.cancel()
        schedulerTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.tickScheduler()
                try? await Task.sleep(nanoseconds: 8_000_000)
            }
        }
    }

    private func tickScheduler() {
        guard isRunning else { return }

        let lookAhead: TimeInterval = 0.02
        let now = ProcessInfo.processInfo.systemUptime
        let stallThreshold: TimeInterval = 0.2

        if nextStepTime == 0 {
            nextStepTime = now + lookAhead
        } else if now > nextStepTime + stallThreshold {
            nextStepTime = now + lookAhead
        }

        var scheduled = 0
        while now + lookAhead >= nextStepTime, scheduled < 3 {
            scheduleStep()

            let duration = max(0.008, stepDurationSeconds(for: currentStep))
            nextStepTime += duration

            scheduled += 1
        }
    }

    private func scheduleStep() {
        let stepInBar = currentStep % stepsPerBar
        let stepInBeat = stepInBar % max(1, subdivision.rawValue)
        let isPrimaryBeatStep = stepInBeat == 0
        let isDownbeat = stepInBar == 0

        if isPrimaryBeatStep {
            triggerClick(isDownbeat: isDownbeat)
            beatPulseID &+= 1
        } else {
            triggerClick(isDownbeat: false, offbeat: true)
        }

        if grooveEnabled && !isCountInActive {
            let events = groovePatternByStep[stepInBar] ?? []
            for event in events {
                triggerGroove(event: event)
            }
        }

        if hapticsEnabled && isPrimaryBeatStep {
            Task { @MainActor in
                let generator = UIImpactFeedbackGenerator(style: isDownbeat ? .medium : .light)
                generator.impactOccurred()
            }
        }

        currentStep += 1
        if currentStep.isMultiple(of: stepsPerBar) {
            currentBar += 1
        }

        if countInStepsRemaining > 0 {
            countInStepsRemaining -= 1
            isCountInActive = countInStepsRemaining > 0
        }
    }

    private var stepsPerBar: Int {
        max(1, meter.top * max(1, subdivision.rawValue))
    }

    private func stepDurationSeconds(for absoluteStep: Int) -> Double {
        let beatUnit = (60.0 / bpm) * (4.0 / Double(meter.bottom))
        let stepsPerBeat = max(1, subdivision.rawValue)

        var duration = beatUnit / Double(stepsPerBeat)

        if subdivision == .eighth {
            let stepInBeat = absoluteStep % stepsPerBeat
            let longPortion = 0.5 + (0.2 * swingAmount)
            if stepInBeat == 0 {
                duration = beatUnit * longPortion
            } else {
                duration = beatUnit * (1 - longPortion)
            }
        }

        if humanizeMs > 0 {
            duration += Double.random(in: -humanizeMs...humanizeMs) / 1_000
        }

        return max(0.008, duration)
    }

    private func setupAudioGraphIfNeeded() {
        guard enableAudioIO else { return }
        guard sourceNode == nil else { return }

        let outputFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        let renderLock = renderStateLock

        renderLock.withLock { state in
            let outputRate = outputFormat.sampleRate
            state.sampleRate = outputRate > 1_000 ? outputRate : 44_100
        }

        let node = Self.makeSourceNode(renderLock: renderLock)

        sourceNode = node
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: outputFormat)
        audioEngine.mainMixerNode.outputVolume = 1
    }

    private nonisolated static func makeSourceNode(
        renderLock: OSAllocatedUnfairLock<RenderState>
    ) -> AVAudioSourceNode {
        AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let audioBuffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let channelCount = Int(audioBufferList.pointee.mNumberBuffers)

            renderLock.withLock { state in
                let sampleRate = max(1, state.sampleRate)

                for frame in 0..<Int(frameCount) {
                    var mixedSample = 0.0

                    if !state.activeVoices.isEmpty {
                        var index = 0
                        while index < state.activeVoices.count {
                            var voice = state.activeVoices[index]
                            let tonal = sin(voice.phase)

                            let sample: Double
                            if voice.noiseMix > 0 {
                                var seed = state.noiseState
                                seed ^= seed << 13
                                seed ^= seed >> 7
                                seed ^= seed << 17
                                state.noiseState = seed
                                let noise = (Double(seed & 0xFFFF) / 32767.5) - 1.0
                                sample = (tonal * (1 - voice.noiseMix)) + (noise * voice.noiseMix)
                            } else {
                                sample = tonal
                            }

                            mixedSample += sample * voice.amplitude

                            voice.phase += (2 * .pi * voice.frequency) / sampleRate
                            if voice.phase >= (2 * .pi) {
                                voice.phase -= (2 * .pi)
                            }

                            voice.amplitude *= voice.decayPerSample
                            voice.remainingSamples -= 1

                            if voice.remainingSamples <= 0 || voice.amplitude < 0.0001 {
                                state.activeVoices.remove(at: index)
                            } else {
                                state.activeVoices[index] = voice
                                index += 1
                            }
                        }
                    }

                    let clamped = Float(max(-1, min(1, mixedSample)))
                    for channel in 0..<channelCount {
                        let pointer = audioBuffers[channel].mData?.assumingMemoryBound(to: Float.self)
                        pointer?[frame] = clamped
                    }
                }
            }

            return noErr
        }
    }

    private func syncRenderSampleRateFromOutput() {
        guard enableAudioIO else { return }
        let outputFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        renderStateLock.withLock { state in
            let outputRate = outputFormat.sampleRate
            state.sampleRate = outputRate > 1_000 ? outputRate : 44_100
        }
    }

    private func triggerClick(isDownbeat: Bool, offbeat: Bool = false) {
        let useAlternateSubdivisionSound = offbeat && subdivisionUsesAlternateClick
        let spec = clickVoiceSpec(isDownbeat: isDownbeat, offbeat: useAlternateSubdivisionSound)
        let accent: Double
        if offbeat {
            accent = subdivisionUsesAlternateClick ? 0.4 : 0.55
        } else {
            accent = isDownbeat ? 1.0 : 0.72
        }
        triggerVoice(spec: spec, accent: accent)
    }

    private func triggerGroove(event: GrooveEvent) {
        let strong = event.accent >= 0.72
        let accent = max(0, min(1, event.accent))

        switch event.voice {
        case .kick:
            triggerVoice(spec: kickBodySpec(strong: strong), accent: accent)
            triggerVoice(spec: kickClickSpec(strong: strong), accent: accent)
        case .snare:
            triggerVoice(spec: snareBodySpec(strong: strong), accent: accent)
            triggerVoice(spec: snareNoiseSpec(strong: strong), accent: accent)
        case .hihat:
            triggerVoice(spec: hatMetalSpec(strong: strong), accent: accent)
            triggerVoice(spec: hatNoiseSpec(strong: strong), accent: accent)
        }
    }

    private func triggerVoice(spec: VoiceSpec, accent: Double) {
        guard enableAudioIO else { return }
        guard isRunning else { return }
        guard audioEngine.isRunning else { return }

        let baseAmp = spec.amplitude * max(0, min(1, masterVolume)) * max(0, accent)
        guard baseAmp > 0 else { return }

        renderStateLock.withLock { state in
            let sampleRate = max(1, state.sampleRate)
            let remaining = max(1, Int(spec.durationSeconds * sampleRate))
            let decayPerSample = exp(-1.0 / max(1.0, spec.decaySeconds * sampleRate))

            state.activeVoices.append(
                ActiveVoice(
                    phase: 0,
                    frequency: spec.frequency,
                    amplitude: baseAmp,
                    decayPerSample: decayPerSample,
                    remainingSamples: remaining,
                    noiseMix: max(0, min(1, spec.noiseMix))
                )
            )

            if state.activeVoices.count > 64 {
                state.activeVoices.removeFirst(state.activeVoices.count - 64)
            }
        }
    }

    private func clickVoiceSpec(isDownbeat: Bool, offbeat: Bool) -> VoiceSpec {
        switch soundSet {
        case .woodblock:
            return VoiceSpec(
                frequency: isDownbeat ? 1520 : (offbeat ? 1020 : 1240),
                amplitude: isDownbeat ? 0.95 : (offbeat ? 0.45 : 0.7),
                durationSeconds: offbeat ? 0.04 : 0.07,
                decaySeconds: offbeat ? 0.02 : 0.04,
                noiseMix: 0.05
            )
        case .hihat:
            return VoiceSpec(
                frequency: isDownbeat ? 6200 : (offbeat ? 4800 : 5600),
                amplitude: isDownbeat ? 0.85 : (offbeat ? 0.4 : 0.65),
                durationSeconds: offbeat ? 0.03 : 0.05,
                decaySeconds: offbeat ? 0.012 : 0.018,
                noiseMix: 0.82
            )
        case .rim:
            return VoiceSpec(
                frequency: isDownbeat ? 1080 : (offbeat ? 760 : 920),
                amplitude: isDownbeat ? 0.92 : (offbeat ? 0.42 : 0.68),
                durationSeconds: offbeat ? 0.04 : 0.06,
                decaySeconds: offbeat ? 0.018 : 0.032,
                noiseMix: 0.18
            )
        case .digital:
            return VoiceSpec(
                frequency: isDownbeat ? 1920 : (offbeat ? 1500 : 1700),
                amplitude: isDownbeat ? 0.9 : (offbeat ? 0.44 : 0.68),
                durationSeconds: offbeat ? 0.03 : 0.05,
                decaySeconds: offbeat ? 0.016 : 0.024,
                noiseMix: 0.0
            )
        case .cowbell:
            return VoiceSpec(
                frequency: isDownbeat ? 910 : (offbeat ? 760 : 860),
                amplitude: isDownbeat ? 0.95 : (offbeat ? 0.5 : 0.72),
                durationSeconds: offbeat ? 0.045 : 0.07,
                decaySeconds: offbeat ? 0.026 : 0.04,
                noiseMix: 0.12
            )
        case .clave:
            return VoiceSpec(
                frequency: isDownbeat ? 1880 : (offbeat ? 1500 : 1710),
                amplitude: isDownbeat ? 0.9 : (offbeat ? 0.46 : 0.7),
                durationSeconds: offbeat ? 0.03 : 0.05,
                decaySeconds: offbeat ? 0.016 : 0.023,
                noiseMix: 0.07
            )
        case .shaker:
            return VoiceSpec(
                frequency: isDownbeat ? 4200 : (offbeat ? 3600 : 3900),
                amplitude: isDownbeat ? 0.76 : (offbeat ? 0.48 : 0.62),
                durationSeconds: offbeat ? 0.035 : 0.05,
                decaySeconds: offbeat ? 0.014 : 0.02,
                noiseMix: 0.9
            )
        case .tick:
            return VoiceSpec(
                frequency: isDownbeat ? 2800 : (offbeat ? 2250 : 2500),
                amplitude: isDownbeat ? 0.82 : (offbeat ? 0.4 : 0.6),
                durationSeconds: offbeat ? 0.022 : 0.035,
                decaySeconds: offbeat ? 0.011 : 0.016,
                noiseMix: 0.02
            )
        case .sidestick:
            return VoiceSpec(
                frequency: isDownbeat ? 1760 : (offbeat ? 1360 : 1520),
                amplitude: isDownbeat ? 0.88 : (offbeat ? 0.4 : 0.65),
                durationSeconds: offbeat ? 0.028 : 0.044,
                decaySeconds: offbeat ? 0.012 : 0.018,
                noiseMix: 0.26
            )
        case .triangle:
            return VoiceSpec(
                frequency: isDownbeat ? 3380 : (offbeat ? 2860 : 3100),
                amplitude: isDownbeat ? 0.8 : (offbeat ? 0.44 : 0.66),
                durationSeconds: offbeat ? 0.045 : 0.075,
                decaySeconds: offbeat ? 0.032 : 0.048,
                noiseMix: 0.0
            )
        case .analogPulse:
            return VoiceSpec(
                frequency: isDownbeat ? 1480 : (offbeat ? 1120 : 1280),
                amplitude: isDownbeat ? 0.86 : (offbeat ? 0.4 : 0.62),
                durationSeconds: offbeat ? 0.03 : 0.045,
                decaySeconds: offbeat ? 0.016 : 0.024,
                noiseMix: 0.08
            )
        case .beep:
            return VoiceSpec(
                frequency: isDownbeat ? 2060 : (offbeat ? 1640 : 1840),
                amplitude: isDownbeat ? 0.88 : (offbeat ? 0.42 : 0.64),
                durationSeconds: offbeat ? 0.03 : 0.044,
                decaySeconds: offbeat ? 0.014 : 0.021,
                noiseMix: 0.0
            )
        case .pip:
            return VoiceSpec(
                frequency: isDownbeat ? 2740 : (offbeat ? 2240 : 2460),
                amplitude: isDownbeat ? 0.78 : (offbeat ? 0.36 : 0.58),
                durationSeconds: offbeat ? 0.02 : 0.032,
                decaySeconds: offbeat ? 0.01 : 0.015,
                noiseMix: 0.02
            )
        case .block:
            return VoiceSpec(
                frequency: isDownbeat ? 1560 : (offbeat ? 1120 : 1320),
                amplitude: isDownbeat ? 0.94 : (offbeat ? 0.46 : 0.7),
                durationSeconds: offbeat ? 0.04 : 0.062,
                decaySeconds: offbeat ? 0.019 : 0.03,
                noiseMix: 0.09
            )
        case .snap:
            return VoiceSpec(
                frequency: isDownbeat ? 1880 : (offbeat ? 1460 : 1680),
                amplitude: isDownbeat ? 0.8 : (offbeat ? 0.42 : 0.62),
                durationSeconds: offbeat ? 0.024 : 0.038,
                decaySeconds: offbeat ? 0.01 : 0.015,
                noiseMix: 0.44
            )
        case .bongo:
            return VoiceSpec(
                frequency: isDownbeat ? 470 : (offbeat ? 360 : 420),
                amplitude: isDownbeat ? 0.92 : (offbeat ? 0.52 : 0.7),
                durationSeconds: offbeat ? 0.052 : 0.08,
                decaySeconds: offbeat ? 0.028 : 0.044,
                noiseMix: 0.15
            )
        case .conga:
            return VoiceSpec(
                frequency: isDownbeat ? 360 : (offbeat ? 280 : 320),
                amplitude: isDownbeat ? 0.94 : (offbeat ? 0.54 : 0.72),
                durationSeconds: offbeat ? 0.056 : 0.088,
                decaySeconds: offbeat ? 0.03 : 0.048,
                noiseMix: 0.12
            )
        case .cabasa:
            return VoiceSpec(
                frequency: isDownbeat ? 4250 : (offbeat ? 3520 : 3920),
                amplitude: isDownbeat ? 0.74 : (offbeat ? 0.48 : 0.61),
                durationSeconds: offbeat ? 0.034 : 0.052,
                decaySeconds: offbeat ? 0.013 : 0.019,
                noiseMix: 0.92
            )
        case .clap:
            return VoiceSpec(
                frequency: isDownbeat ? 2420 : (offbeat ? 1880 : 2150),
                amplitude: isDownbeat ? 0.84 : (offbeat ? 0.44 : 0.64),
                durationSeconds: offbeat ? 0.028 : 0.05,
                decaySeconds: offbeat ? 0.012 : 0.021,
                noiseMix: 0.72
            )
        }
    }

    private func kickBodySpec(strong: Bool) -> VoiceSpec {
        VoiceSpec(
            frequency: strong ? 74 : 66,
            amplitude: strong ? 0.85 : 0.68,
            durationSeconds: strong ? 0.16 : 0.13,
            decaySeconds: strong ? 0.11 : 0.09,
            noiseMix: 0.04
        )
    }

    private func kickClickSpec(strong: Bool) -> VoiceSpec {
        VoiceSpec(
            frequency: strong ? 1620 : 1480,
            amplitude: strong ? 0.26 : 0.2,
            durationSeconds: 0.015,
            decaySeconds: 0.008,
            noiseMix: 0.35
        )
    }

    private func snareBodySpec(strong: Bool) -> VoiceSpec {
        VoiceSpec(
            frequency: strong ? 210 : 186,
            amplitude: strong ? 0.5 : 0.4,
            durationSeconds: 0.075,
            decaySeconds: 0.038,
            noiseMix: 0.2
        )
    }

    private func snareNoiseSpec(strong: Bool) -> VoiceSpec {
        VoiceSpec(
            frequency: strong ? 2900 : 2500,
            amplitude: strong ? 0.62 : 0.46,
            durationSeconds: strong ? 0.06 : 0.05,
            decaySeconds: strong ? 0.024 : 0.02,
            noiseMix: 0.92
        )
    }

    private func hatMetalSpec(strong: Bool) -> VoiceSpec {
        VoiceSpec(
            frequency: strong ? 6100 : 5600,
            amplitude: strong ? 0.3 : 0.22,
            durationSeconds: 0.03,
            decaySeconds: 0.012,
            noiseMix: 0.2
        )
    }

    private func hatNoiseSpec(strong: Bool) -> VoiceSpec {
        VoiceSpec(
            frequency: strong ? 6800 : 6200,
            amplitude: strong ? 0.5 : 0.38,
            durationSeconds: strong ? 0.04 : 0.03,
            decaySeconds: strong ? 0.017 : 0.013,
            noiseMix: 0.96
        )
    }

    private func refreshPattern() {
        let pattern = grooveGenerator.generate(
            style: grooveStyle,
            meter: meter,
            subdivision: subdivision,
            intensity: grooveIntensity
        )

        var grouped: [Int: [GrooveEvent]] = [:]
        for event in pattern.events {
            grouped[event.step, default: []].append(event)
        }
        groovePatternByStep = grouped
    }

    private func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.max(lower, Swift.min(upper, value))
    }

    private func configureAudioSessionIfNeeded() throws {
        guard !audioSessionConfigured else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        audioSessionConfigured = true
    }

}
