import AVFoundation
import AudioToolbox
import Foundation

enum TheoryPlaybackSound: String, CaseIterable, Identifiable {
    static let defaultsKey = "theory.playback.sound"

    case grandPiano
    case brightPiano
    case electricPiano
    case vibraphone
    case nylonGuitar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grandPiano: "Grand Piano"
        case .brightPiano: "Bright Piano"
        case .electricPiano: "Electric Piano"
        case .vibraphone: "Vibraphone"
        case .nylonGuitar: "Nylon Guitar"
        }
    }

    var program: UInt8 {
        switch self {
        case .grandPiano: 0
        case .brightPiano: 1
        case .electricPiano: 4
        case .vibraphone: 11
        case .nylonGuitar: 24
        }
    }

    static var defaultValue: TheoryPlaybackSound { .grandPiano }

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> TheoryPlaybackSound {
        guard
            let raw = defaults.string(forKey: defaultsKey),
            let sound = TheoryPlaybackSound(rawValue: raw)
        else {
            return defaultValue
        }
        return sound
    }
}

final class SimpleSynth: ObservableObject, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private let reverb = AVAudioUnitReverb()
    private let defaults: UserDefaults
    private let audioQueue = DispatchQueue(label: "com.nbz.improvbuddy.theoryPlayback", qos: .userInitiated)
    private var loadedSound: TheoryPlaybackSound?
    private var activeNotes = Set<UInt8>()
    private var hasConfiguredGraph = false
    private var scheduledPlaybackWorkItems: [DispatchWorkItem] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func playMIDINotes(_ notes: [Int], noteDuration: Double = 0.28, velocity: UInt8 = 90) {
        let midiNotes = sanitize(notes)
        guard !midiNotes.isEmpty else { return }

        audioQueue.async { [weak self] in
            guard let self else { return }
            self.ensureEngineStartedIfNeeded()
            self.cancelScheduledPlaybackLocked()
            self.stopAllActiveNotesLocked()

            let safeNoteDuration = max(0.08, noteDuration)
            let hold = safeNoteDuration * 0.82

            for (index, midi) in midiNotes.enumerated() {
                let startDelay = safeNoteDuration * Double(index)
                let stopDelay = startDelay + hold

                let startWork = DispatchWorkItem { [weak self] in
                    self?.startLocked(note: midi, velocity: velocity)
                }
                self.scheduledPlaybackWorkItems.append(startWork)
                self.audioQueue.asyncAfter(deadline: .now() + startDelay, execute: startWork)

                let stopWork = DispatchWorkItem { [weak self] in
                    self?.stopLocked(note: midi)
                }
                self.scheduledPlaybackWorkItems.append(stopWork)
                self.audioQueue.asyncAfter(deadline: .now() + stopDelay, execute: stopWork)
            }
        }
    }

    func playChordMIDINotes(_ notes: [Int], duration: Double = 0.95, velocity: UInt8 = 95) {
        let midiNotes = sanitize(notes)
        guard !midiNotes.isEmpty else { return }

        audioQueue.async { [weak self] in
            guard let self else { return }
            self.ensureEngineStartedIfNeeded()
            self.cancelScheduledPlaybackLocked()
            self.stopAllActiveNotesLocked()

            for midi in midiNotes {
                self.startLocked(note: midi, velocity: velocity)
            }

            let stopDelay = max(0.12, duration)
            let stopWork = DispatchWorkItem { [weak self] in
                guard let self else { return }
                for midi in midiNotes {
                    self.stopLocked(note: midi)
                }
            }
            self.scheduledPlaybackWorkItems.append(stopWork)
            self.audioQueue.asyncAfter(deadline: .now() + stopDelay, execute: stopWork)
        }
    }

    func play(frequency: Double, amplitude: Double) {
        let safeFrequency = max(20, frequency)
        let midiFloat = 69.0 + 12.0 * log2(safeFrequency / 440.0)
        let midi = Int(round(midiFloat))
        let velocity = UInt8(max(24, min(127, Int(round(amplitude * 127)))))
        playMIDINotes([midi], noteDuration: 0.26, velocity: velocity)
    }

    func startSustainedMIDINote(_ note: Int, velocity: UInt8 = 96) {
        guard let midi = sanitize([note]).first else { return }

        audioQueue.async { [weak self] in
            guard let self else { return }
            self.ensureEngineStartedIfNeeded()
            self.cancelScheduledPlaybackLocked()
            self.stopAllActiveNotesLocked()
            self.startLocked(note: midi, velocity: velocity)
        }
    }

    func stopSustainedMIDINote() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.cancelScheduledPlaybackLocked()
            self.stopAllActiveNotesLocked()
        }
    }

    func stopTone() {
        stopSustainedMIDINote()
    }

    private func ensureEngineStartedIfNeeded() {
        configureGraphIfNeeded()
        applySoundSelectionIfNeeded(force: false)

        guard !engine.isRunning else { return }

#if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Best effort: engine can still start in many simulator/device states.
        }
#endif

        do {
            engine.prepare()
            try engine.start()
        } catch {
            // Keep silent failure for UI responsiveness and to avoid crashes in edge routes.
        }
    }

    private func configureGraphIfNeeded() {
        guard !hasConfiguredGraph else { return }
        hasConfiguredGraph = true

        engine.attach(sampler)
        engine.attach(reverb)

        reverb.loadFactoryPreset(.mediumHall2)
        reverb.wetDryMix = 14

        engine.connect(sampler, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = 0.95
    }

    private func applySoundSelectionIfNeeded(force: Bool) {
        let selectedSound = TheoryPlaybackSound.fromDefaults(defaults)
        guard force || selectedSound != loadedSound else { return }

        guard let bankURL = locateSoundBankURL() else {
            loadedSound = nil
            return
        }

        do {
            try sampler.loadSoundBankInstrument(
                at: bankURL,
                program: selectedSound.program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            loadedSound = selectedSound
        } catch {
            loadedSound = nil
        }
    }

    private func locateSoundBankURL() -> URL? {
        let candidates = [
            "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls",
            "/System/Library/Audio/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls",
            "/System/Library/Audio/Unit Plug-Ins/Components/DLSMusicDevice.component/Contents/Resources/gs_instruments.dls"
        ]

        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func sanitize(_ notes: [Int]) -> [UInt8] {
        notes.compactMap { note in
            guard (0...127).contains(note) else { return nil }
            return UInt8(note)
        }
    }

    private func startLocked(note: UInt8, velocity: UInt8) {
        sampler.startNote(note, withVelocity: velocity, onChannel: 0)
        activeNotes.insert(note)
    }

    private func stopLocked(note: UInt8) {
        sampler.stopNote(note, onChannel: 0)
        activeNotes.remove(note)
    }

    private func stopAllActiveNotesLocked() {
        for note in activeNotes {
            sampler.stopNote(note, onChannel: 0)
        }
        activeNotes.removeAll()
    }

    private func cancelScheduledPlaybackLocked() {
        for workItem in scheduledPlaybackWorkItems {
            workItem.cancel()
        }
        scheduledPlaybackWorkItems.removeAll()
    }
}
