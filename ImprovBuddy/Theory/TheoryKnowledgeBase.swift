import CryptoKit
import Foundation

final class TheoryKnowledgeBase {
    let envelope: TheoryDatasetEnvelope
    let checksum: String
    let validationIssues: [String]

    private(set) var scalesByID: [String: TheoryScaleDefinition] = [:]
    private(set) var arpeggiosByID: [String: TheoryArpeggioDefinition] = [:]
    private(set) var chordsByID: [String: TheoryChordDefinition] = [:]
    private(set) var recommendationsByChordID: [String: [ChordScaleRecommendation]] = [:]
    private(set) var guideToneRulesByID: [String: GuideToneRule] = [:]
    private(set) var avoidToneRulesByID: [String: AvoidToneRule] = [:]
    private(set) var voiceLeadingRulesByID: [String: VoiceLeadingRule] = [:]

    private(set) var chordIDsBySymbol: [String: String] = [:]

    static func load(bundle: Bundle = .main) -> TheoryKnowledgeBase {
        guard
            let url = bundle.url(forResource: "theory_library_v1", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let envelope = try? JSONDecoder().decode(TheoryDatasetEnvelope.self, from: data)
        else {
            return TheoryKnowledgeBase(envelope: Self.fallbackEnvelope())
        }

        return TheoryKnowledgeBase(envelope: envelope)
    }

    init(envelope: TheoryDatasetEnvelope) {
        self.envelope = envelope
        checksum = Self.hash(dataset: envelope.dataset)

        scalesByID = Dictionary(uniqueKeysWithValues: envelope.dataset.scales.map { ($0.id, $0) })
        arpeggiosByID = Dictionary(uniqueKeysWithValues: envelope.dataset.arpeggios.map { ($0.id, $0) })
        chordsByID = Dictionary(uniqueKeysWithValues: envelope.dataset.chords.map { ($0.id, $0) })
        guideToneRulesByID = Dictionary(uniqueKeysWithValues: envelope.dataset.guideToneRules.map { ($0.id, $0) })
        avoidToneRulesByID = Dictionary(uniqueKeysWithValues: envelope.dataset.avoidToneRules.map { ($0.id, $0) })
        voiceLeadingRulesByID = Dictionary(uniqueKeysWithValues: envelope.dataset.voiceLeadingRules.map { ($0.id, $0) })

        for chord in envelope.dataset.chords {
            for symbol in chord.symbols {
                chordIDsBySymbol[symbol.lowercased()] = chord.id
            }
        }

        let grouped = Dictionary(grouping: envelope.dataset.recommendations, by: \.chordID)
        recommendationsByChordID = grouped.mapValues { recs in
            recs.sorted {
                if $0.relevance != $1.relevance { return $0.relevance > $1.relevance }
                if $0.tensionLevel != $1.tensionLevel { return $0.tensionLevel < $1.tensionLevel }
                return $0.id < $1.id
            }
        }

        validationIssues = Self.validate(envelope: envelope)
    }

    func chordDefinition(id: String) -> TheoryChordDefinition? {
        chordsByID[id]
    }

    func recommendations(chordID: String) -> [ChordScaleRecommendation] {
        recommendationsByChordID[chordID] ?? []
    }

    func chordID(for chord: Chord) -> String? {
        let key = inferredSymbol(for: chord).lowercased()
        if let direct = chordIDsBySymbol[key] {
            return direct
        }

        switch chord.quality {
        case .major:
            if chord.extensions.contains(7) { return "maj7" }
            return "maj_tri"
        case .minor:
            if chord.extensions.contains(7) { return "min7" }
            return "min_tri"
        case .dominant:
            if !chord.alterations.isEmpty { return "dom7alt" }
            if chord.extensions.contains(7) { return "dom7" }
            return "dom7"
        case .halfDiminished:
            return "m7b5"
        case .diminished:
            if chord.extensions.contains(7) { return "dim7" }
            return "dim_tri"
        case .suspended:
            return "dom7sus"
        case .augmented:
            if chord.extensions.contains(7) { return "aug_maj7" }
            return "aug_tri"
        }
    }

    private func inferredSymbol(for chord: Chord) -> String {
        switch chord.quality {
        case .major:
            if chord.extensions.contains(7) { return "maj7" }
            return "maj"
        case .minor:
            if chord.extensions.contains(7) { return "m7" }
            return "m"
        case .dominant:
            if chord.alterations.isEmpty { return "7" }
            return "7alt"
        case .halfDiminished:
            return "m7b5"
        case .diminished:
            if chord.extensions.contains(7) { return "dim7" }
            return "dim"
        case .suspended:
            return "7sus"
        case .augmented:
            if chord.extensions.contains(7) { return "augmaj7" }
            return "aug"
        }
    }

    static func hash(dataset: TheoryDataset) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = (try? encoder.encode(dataset)) ?? Data()
        let canonicalBytes: Data
        if
            let object = try? JSONSerialization.jsonObject(with: bytes),
            let canonical = canonicalJSONString(for: object).data(using: .utf8)
        {
            canonicalBytes = canonical
        } else {
            canonicalBytes = bytes
        }
        let digest = SHA256.hash(data: canonicalBytes)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalJSONString(for value: Any) -> String {
        switch value {
        case let dictionary as [String: Any]:
            let body = dictionary
                .keys
                .sorted()
                .map { key in
                    "\(escapedJSONString(key)):\(canonicalJSONString(for: dictionary[key] ?? NSNull()))"
                }
                .joined(separator: ",")
            return "{\(body)}"

        case let array as [Any]:
            let body = array.map { canonicalJSONString(for: $0) }.joined(separator: ",")
            return "[\(body)]"

        case let string as String:
            return escapedJSONString(string)

        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue

        case _ as NSNull:
            return "null"

        default:
            return "null"
        }
    }

    private static func escapedJSONString(_ string: String) -> String {
        var output = "\""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x22:
                output += "\\\""
            case 0x5C:
                output += "\\\\"
            case 0x08:
                output += "\\b"
            case 0x0C:
                output += "\\f"
            case 0x0A:
                output += "\\n"
            case 0x0D:
                output += "\\r"
            case 0x09:
                output += "\\t"
            case 0x20...0x7E:
                output.append(Character(scalar))
            case 0x00...0x1F:
                output += String(format: "\\u%04x", scalar.value)
            default:
                if scalar.value <= 0xFFFF {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    let value = scalar.value - 0x10000
                    let high = 0xD800 + (value >> 10)
                    let low = 0xDC00 + (value & 0x3FF)
                    output += String(format: "\\u%04x\\u%04x", high, low)
                }
            }
        }
        output += "\""
        return output
    }

    static func validate(envelope: TheoryDatasetEnvelope) -> [String] {
        var issues: [String] = []

        if envelope.schemaVersion <= 0 {
            issues.append("Invalid schema version.")
        }

        let computedChecksum = hash(dataset: envelope.dataset)
        if envelope.checksumSHA256.lowercased() != computedChecksum.lowercased() {
            issues.append("Dataset checksum mismatch.")
        }

        let scaleIDs = Set(envelope.dataset.scales.map(\.id))
        let arpeggioIDs = Set(envelope.dataset.arpeggios.map(\.id))
        let chordIDs = Set(envelope.dataset.chords.map(\.id))
        let guideIDs = Set(envelope.dataset.guideToneRules.map(\.id))
        let avoidIDs = Set(envelope.dataset.avoidToneRules.map(\.id))
        let voiceIDs = Set(envelope.dataset.voiceLeadingRules.map(\.id))

        for recommendation in envelope.dataset.recommendations {
            if !chordIDs.contains(recommendation.chordID) {
                issues.append("Recommendation \(recommendation.id) references unknown chord \(recommendation.chordID).")
            }
            if !scaleIDs.contains(recommendation.primaryScaleID) {
                issues.append("Recommendation \(recommendation.id) missing scale \(recommendation.primaryScaleID).")
            }
            for id in recommendation.alternativeScaleIDs where !scaleIDs.contains(id) {
                issues.append("Recommendation \(recommendation.id) missing alternative scale \(id).")
            }
            for id in recommendation.arpeggioIDs where !arpeggioIDs.contains(id) {
                issues.append("Recommendation \(recommendation.id) missing arpeggio \(id).")
            }
            if let id = recommendation.guideToneRuleID, !guideIDs.contains(id) {
                issues.append("Recommendation \(recommendation.id) missing guide-tone rule \(id).")
            }
            for id in recommendation.avoidToneRuleIDs where !avoidIDs.contains(id) {
                issues.append("Recommendation \(recommendation.id) missing avoid-tone rule \(id).")
            }
            for id in recommendation.voiceLeadingRuleIDs where !voiceIDs.contains(id) {
                issues.append("Recommendation \(recommendation.id) missing voice-leading rule \(id).")
            }
        }

        return issues
    }

    static func fallbackEnvelope() -> TheoryDatasetEnvelope {
        let dataset = TheoryDataset(
            source: "fallback",
            scales: [
                TheoryScaleDefinition(
                    id: "ionian",
                    name: "Ionian",
                    family: "Major Modes",
                    intervals: [0, 2, 4, 5, 7, 9, 11],
                    degreeSteps: [0, 1, 2, 3, 4, 5, 6],
                    tier: .core,
                    tags: ["major"],
                    summary: "Major scale foundation."
                )
            ],
            arpeggios: [
                TheoryArpeggioDefinition(
                    id: "maj7_arp",
                    name: "Maj7 Arpeggio",
                    family: "Seventh Arpeggios",
                    intervals: [0, 4, 7, 11],
                    degreeSteps: [0, 2, 4, 6],
                    tier: .core,
                    tags: ["major"],
                    summary: "Chord-tone map for major seven."
                )
            ],
            chords: [
                TheoryChordDefinition(
                    id: "maj7",
                    name: "Maj7",
                    symbols: ["maj7", "maj"],
                    quality: .major,
                    intervals: [0, 4, 7, 11],
                    degreeSteps: [0, 2, 4, 6],
                    tier: .core,
                    functionHints: [.tonic],
                    family: "Major",
                    summary: "Stable tonic color."
                )
            ],
            recommendations: [
                ChordScaleRecommendation(
                    id: "maj7_core",
                    chordID: "maj7",
                    primaryScaleID: "ionian",
                    alternativeScaleIDs: [],
                    arpeggioIDs: ["maj7_arp"],
                    guideToneRuleID: nil,
                    avoidToneRuleIDs: [],
                    voiceLeadingRuleIDs: [],
                    tensionLevel: 0,
                    relevance: 100,
                    tier: .core,
                    functionTag: .tonic,
                    recommendedDrillIDs: ["chord_tone_anchors"],
                    rationale: "Default major tonic color."
                )
            ],
            guideToneRules: [],
            avoidToneRules: [],
            voiceLeadingRules: []
        )
        return TheoryDatasetEnvelope(
            schemaVersion: 1,
            checksumSHA256: hash(dataset: dataset),
            dataset: dataset
        )
    }
}
