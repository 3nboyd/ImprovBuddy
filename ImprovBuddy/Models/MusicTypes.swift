import Combine
import Foundation

enum FeelType: String, Codable, CaseIterable, Identifiable {
    case straight
    case swing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .straight: "Straight"
        case .swing: "Swing"
        }
    }
}

enum InputMode: String, Codable, CaseIterable, Identifiable {
    case mic
    case midi
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mic: "Mic"
        case .midi: "MIDI"
        case .both: "Both"
        }
    }
}

enum HarmonyClass: String, Codable, CaseIterable, Identifiable {
    case chordTone
    case tension
    case approach
    case outside

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chordTone: "Chord Tone"
        case .tension: "Tension"
        case .approach: "Approach"
        case .outside: "Outside"
        }
    }
}

enum EventSource: String, Codable, CaseIterable {
    case mic
    case midi
}

struct TimeValuePair: Codable, Hashable {
    var time: TimeInterval
    var value: Double
}

struct PitchTracePoint: Codable, Hashable {
    var time: TimeInterval
    var midiNote: Double
    var confidence: Double
    var source: EventSource
}

struct HarmonyTracePoint: Codable, Hashable {
    var time: TimeInterval
    var state: HarmonyClass
}

struct TempoDriftStats: Codable, Hashable {
    var meanAbsoluteErrorMs: Double
    var signedBiasMs: Double
    var driftSlope: Double
    var stabilityScore: Double
}

struct PocketBiasStats: Codable, Hashable {
    var aheadPct: Double
    var behindPct: Double
    var centeredPct: Double
    var meanBiasMs: Double
}

struct SwingStats: Codable, Hashable {
    var averageRatio: Double
    var consistencyStdDev: Double
}

struct HarmonyStats: Codable, Hashable {
    var chordTonePct: Double
    var extensionPct: Double
    var approachPct: Double
    var outsidePct: Double
    var downbeatChordTonePct: Double
    var resolutionRate: Double
    var rootOverusePct: Double
}

struct SessionSummaryMetrics: Codable, Hashable {
    var tempoDrift: TempoDriftStats
    var pocket: PocketBiasStats
    var swing: SwingStats
    var harmony: HarmonyStats
    var professorNotesText: String
    var recommendedDrillIDs: [String]

    static let empty = SessionSummaryMetrics(
        tempoDrift: TempoDriftStats(meanAbsoluteErrorMs: 0, signedBiasMs: 0, driftSlope: 0, stabilityScore: 0),
        pocket: PocketBiasStats(aheadPct: 0, behindPct: 0, centeredPct: 1, meanBiasMs: 0),
        swing: SwingStats(averageRatio: 1, consistencyStdDev: 0),
        harmony: HarmonyStats(
            chordTonePct: 0,
            extensionPct: 0,
            approachPct: 0,
            outsidePct: 0,
            downbeatChordTonePct: 0,
            resolutionRate: 0,
            rootOverusePct: 0
        ),
        professorNotesText: "",
        recommendedDrillIDs: []
    )
}

struct RecorderMetronomeReference: Codable, Hashable {
    var bpm: Double
    var meterTop: Int
    var meterBottom: Int
    var subdivision: MetronomeSubdivision
    var metronomeRunningAtStart: Bool
    var startUptime: TimeInterval
    var beatPhaseEstimate: Double
}

enum TunerTemperament: String, Codable, CaseIterable, Identifiable {
    case equal
    case just
    case pythagorean

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .equal: "Equal"
        case .just: "Just"
        case .pythagorean: "Pythagorean"
        }
    }
}

struct TunerSettings: Codable, Hashable {
    var a4Hz: Double
    var temperament: TunerTemperament
    var temperamentRootPitchClass: Int
    var toneChangeSensitivity: Double
    var confidenceGate: Double

    static let `default` = TunerSettings(
        a4Hz: 440,
        temperament: .equal,
        temperamentRootPitchClass: 0,
        toneChangeSensitivity: 0.6,
        confidenceGate: 0.55
    )
}

struct MeterSignature: Codable, Hashable {
    var top: Int
    var bottom: Int

    init(top: Int = 4, bottom: Int = 4) {
        self.top = max(1, min(32, top))
        self.bottom = (bottom == 8) ? 8 : 4
    }

    var displayName: String {
        "\(top)/\(bottom)"
    }
}

enum GrooveStyle: String, Codable, CaseIterable, Identifiable {
    case rock
    case swing
    case funk

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rock: "Rock"
        case .swing: "Swing"
        case .funk: "Funk"
        }
    }
}

struct MetronomeSettings: Codable, Hashable {
    var bpm: Double
    var meter: MeterSignature
    var subdivision: MetronomeSubdivision
    var countInBars: Int
    var soundSet: MetronomeSoundSet
    var masterVolume: Double
    var swingAmount: Double
    var grooveEnabled: Bool
    var grooveStyle: GrooveStyle
    var grooveIntensity: Double
    var humanizeMs: Double
    var hapticsEnabled: Bool

    static let `default` = MetronomeSettings(
        bpm: 120,
        meter: MeterSignature(top: 4, bottom: 4),
        subdivision: .quarter,
        countInBars: 1,
        soundSet: .woodblock,
        masterVolume: 0.8,
        swingAmount: 0.0,
        grooveEnabled: false,
        grooveStyle: .rock,
        grooveIntensity: 0.6,
        humanizeMs: 0,
        hapticsEnabled: false
    )
}

@MainActor
final class ToolsSettingsStore: ObservableObject {
    @Published var tuner: TunerSettings {
        didSet { persist(tuner, key: Keys.tuner) }
    }

    @Published var metronome: MetronomeSettings {
        didSet { persist(metronome, key: Keys.metronome) }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()

    private enum Keys {
        static let tuner = "tools.settings.tuner.v1"
        static let metronome = "tools.settings.metronome.v1"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.tuner = Self.load(defaults: defaults, key: Keys.tuner) ?? .default
        self.metronome = Self.load(defaults: defaults, key: Keys.metronome) ?? .default
    }

    func resetTuner() {
        tuner = .default
    }

    func resetMetronome() {
        metronome = .default
    }

    private static func load<T: Decodable>(defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
