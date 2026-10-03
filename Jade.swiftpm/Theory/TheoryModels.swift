import Foundation

enum TheoryTier: String, Codable, CaseIterable, Identifiable {
    case core
    case extended
    case advanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .core: "Core"
        case .extended: "Extended"
        case .advanced: "Advanced"
        }
    }
}

enum TheoryFunctionTag: String, Codable, CaseIterable, Identifiable {
    case tonic
    case predominant
    case dominant
    case passingDiminished
    case modalInterchange
    case bluesDominant
    case tritoneSub
    case alteredDominant
    case unresolved

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tonic: "Tonic"
        case .predominant: "Predominant"
        case .dominant: "Dominant"
        case .passingDiminished: "Passing Diminished"
        case .modalInterchange: "Modal Interchange"
        case .bluesDominant: "Blues Dominant"
        case .tritoneSub: "Tritone Sub"
        case .alteredDominant: "Altered Dominant"
        case .unresolved: "Unresolved"
        }
    }
}

enum TheoryInstrumentTransposition: String, Codable, CaseIterable, Identifiable {
    case concert
    case bb
    case eb

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .concert: "Concert"
        case .bb: "B♭"
        case .eb: "E♭"
        }
    }

    // Written pitch offset from concert.
    var writtenSemitoneOffset: Int {
        switch self {
        case .concert: 0
        case .bb: 2
        case .eb: 9
        }
    }
}

enum TheoryClef: String, Codable, CaseIterable, Identifiable {
    case treble
    case alto
    case bass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .treble: "Treble"
        case .alto: "Alto"
        case .bass: "Bass"
        }
    }
}

enum TheorySortMode: String, CaseIterable, Identifiable {
    case relevance
    case tension
    case alphabetical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .relevance: "Relevance"
        case .tension: "Tension"
        case .alphabetical: "A-Z"
        }
    }
}

struct TheoryKey: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var rootPitchClass: Int
    var rootLetter: String
    var rootAccidental: String

    static let all: [TheoryKey] = [
        TheoryKey(name: "C", rootPitchClass: 0, rootLetter: "C", rootAccidental: ""),
        TheoryKey(name: "Db", rootPitchClass: 1, rootLetter: "D", rootAccidental: "b"),
        TheoryKey(name: "D", rootPitchClass: 2, rootLetter: "D", rootAccidental: ""),
        TheoryKey(name: "Eb", rootPitchClass: 3, rootLetter: "E", rootAccidental: "b"),
        TheoryKey(name: "E", rootPitchClass: 4, rootLetter: "E", rootAccidental: ""),
        TheoryKey(name: "F", rootPitchClass: 5, rootLetter: "F", rootAccidental: ""),
        TheoryKey(name: "F#", rootPitchClass: 6, rootLetter: "F", rootAccidental: "#"),
        TheoryKey(name: "G", rootPitchClass: 7, rootLetter: "G", rootAccidental: ""),
        TheoryKey(name: "Ab", rootPitchClass: 8, rootLetter: "A", rootAccidental: "b"),
        TheoryKey(name: "A", rootPitchClass: 9, rootLetter: "A", rootAccidental: ""),
        TheoryKey(name: "Bb", rootPitchClass: 10, rootLetter: "B", rootAccidental: "b"),
        TheoryKey(name: "B", rootPitchClass: 11, rootLetter: "B", rootAccidental: "")
    ]

    static var defaultKey: TheoryKey { all[0] }

    static func byName(_ name: String) -> TheoryKey {
        all.first(where: { $0.name == name }) ?? defaultKey
    }

    static func byPitchClass(_ pitchClass: Int, preferSharps: Bool = false) -> TheoryKey {
        let normalized = Chord.normalizePitchClass(pitchClass)
        if preferSharps {
            let sharpNames: [Int: String] = [1: "C#", 3: "D#", 6: "F#", 8: "G#", 10: "A#"]
            if let preferred = sharpNames[normalized] {
                return TheoryKey(
                    name: preferred,
                    rootPitchClass: normalized,
                    rootLetter: String(preferred.prefix(1)),
                    rootAccidental: "#"
                )
            }
        }
        return all.first(where: { $0.rootPitchClass == normalized }) ?? defaultKey
    }
}

struct TheoryContext: Codable, Hashable {
    var concertKeyName: String
    var instrument: TheoryInstrumentTransposition
    var clef: TheoryClef
    var preferredTier: TheoryTier
    var scoringUsesScaleAwareness: Bool

    static let `default` = TheoryContext(
        concertKeyName: TheoryKey.defaultKey.name,
        instrument: .concert,
        clef: .treble,
        preferredTier: .core,
        scoringUsesScaleAwareness: true
    )

    var concertKey: TheoryKey {
        TheoryKey.byName(concertKeyName)
    }
}

struct TheoryScaleDefinition: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var family: String
    var intervals: [Int]
    var degreeSteps: [Int]
    var tier: TheoryTier
    var tags: [String]
    var summary: String
}

struct TheoryArpeggioDefinition: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var family: String
    var intervals: [Int]
    var degreeSteps: [Int]
    var tier: TheoryTier
    var tags: [String]
    var summary: String
}

struct TheoryChordDefinition: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var symbols: [String]
    var quality: ChordQuality
    var intervals: [Int]
    var degreeSteps: [Int]
    var tier: TheoryTier
    var functionHints: [TheoryFunctionTag]
    var family: String
    var summary: String
}

struct ChordScaleRecommendation: Codable, Hashable, Identifiable {
    var id: String
    var chordID: String
    var primaryScaleID: String
    var alternativeScaleIDs: [String]
    var arpeggioIDs: [String]
    var guideToneRuleID: String?
    var avoidToneRuleIDs: [String]
    var voiceLeadingRuleIDs: [String]
    var tensionLevel: Int
    var relevance: Int
    var tier: TheoryTier
    var functionTag: TheoryFunctionTag
    var recommendedDrillIDs: [String]
    var rationale: String
}

struct GuideToneRule: Codable, Hashable, Identifiable {
    var id: String
    var chordID: String
    var intervals: [Int]
    var description: String
}

struct AvoidToneRule: Codable, Hashable, Identifiable {
    var id: String
    var scaleID: String
    var intervals: [Int]
    var description: String
}

struct VoiceLeadingRule: Codable, Hashable, Identifiable {
    var id: String
    var fromChordID: String?
    var toChordID: String?
    var description: String
}

struct TheoryDataset: Codable, Hashable {
    var source: String
    var scales: [TheoryScaleDefinition]
    var arpeggios: [TheoryArpeggioDefinition]
    var chords: [TheoryChordDefinition]
    var recommendations: [ChordScaleRecommendation]
    var guideToneRules: [GuideToneRule]
    var avoidToneRules: [AvoidToneRule]
    var voiceLeadingRules: [VoiceLeadingRule]
}

struct TheoryDatasetEnvelope: Codable, Hashable {
    var schemaVersion: Int
    var checksumSHA256: String
    var dataset: TheoryDataset
}

struct TheoryResolvedOption: Identifiable, Hashable {
    var id: String { recommendation.id }
    var recommendation: ChordScaleRecommendation
    var chord: TheoryChordDefinition
    var primaryScale: TheoryScaleDefinition
    var alternatives: [TheoryScaleDefinition]
    var arpeggios: [TheoryArpeggioDefinition]
    var guideToneRule: GuideToneRule?
    var avoidToneRules: [AvoidToneRule]
    var voiceLeadingRules: [VoiceLeadingRule]
}

enum TheoryDisplayFormatter {
    static func displaySymbol(_ text: String) -> String {
        var output = text
        output = replacingMatches(
            in: output,
            pattern: "([A-G])(bb|##|b|#)"
        ) { match, source in
            guard match.numberOfRanges >= 3 else {
                return source.substring(with: match.range)
            }
            let letter = source.substring(with: match.range(at: 1))
            let accidental = source.substring(with: match.range(at: 2))
            return letter + displayAccidental(accidental)
        }

        output = replacingMatches(
            in: output,
            pattern: "(bb|##|b|#)(?=\\d)"
        ) { match, source in
            guard match.numberOfRanges >= 2 else {
                return source.substring(with: match.range)
            }
            return displayAccidental(source.substring(with: match.range(at: 1)))
        }
        return output
    }

    static func normalizeForSearch(_ text: String) -> String {
        text
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "♯", with: "#")
    }

    private static func displayAccidental(_ accidental: String) -> String {
        switch accidental {
        case "bb":
            return "♭♭"
        case "b":
            return "♭"
        case "##":
            return "♯♯"
        case "#":
            return "♯"
        default:
            return accidental
        }
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        transform: (_ match: NSTextCheckingResult, _ source: NSString) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let source = text as NSString
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        )
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            mutable.replaceCharacters(in: match.range, with: transform(match, source))
        }
        return mutable as String
    }
}

struct SpelledNote: Identifiable, Hashable {
    var id: String { "\(name)\(midi)" }
    var name: String
    var midi: Int
    var pitchClass: Int
    var accidental: String
}

struct StaffRenderedNote: Identifiable, Hashable {
    var id: String { "\(spelled.name)\(spelled.midi)" }
    var spelled: SpelledNote
    var staffStep: Int
}
