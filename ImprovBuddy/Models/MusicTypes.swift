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
