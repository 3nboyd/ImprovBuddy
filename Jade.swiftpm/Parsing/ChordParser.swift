import Foundation

struct ChordParser {
    private static let rootRegex = try! NSRegularExpression(pattern: "^([A-Ga-g])([#b]?)(.*)$")

    static func parse(symbol rawSymbol: String) -> Chord? {
        let symbol = rawSymbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")

        guard !symbol.isEmpty else { return nil }

        let parts = symbol.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let head = String(parts[0])
        let bass = parts.count > 1 ? String(parts[1]) : nil

        guard let (rootPC, descriptorRaw) = parseRootAndDescriptor(from: head) else { return nil }

        let descriptor = descriptorRaw
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")

        let bassPC = bass.flatMap(parsePitchClassOnly)

        var quality: ChordQuality = inferQuality(from: descriptor)
        var extensions = Set<Int>()
        var alterations = Set<ChordAlteration>()
        var addTones = Set<Int>()

        if descriptor.localizedCaseInsensitiveContains("maj7") || descriptor.contains("M7") {
            extensions.insert(7)
            quality = .major
        }

        if descriptor.localizedCaseInsensitiveContains("dim7") || descriptor.contains("o7") || descriptor.contains("°7") {
            quality = .diminished
            extensions.insert(7)
        }

        if descriptor.localizedCaseInsensitiveContains("6") {
            addTones.insert(6)
        }

        if descriptor.contains("7") && !descriptor.localizedCaseInsensitiveContains("maj7") && !descriptor.localizedCaseInsensitiveContains("dim7") {
            extensions.insert(7)
            if quality == .major {
                quality = .dominant
            }
        }

        [9, 11, 13].forEach { number in
            if descriptor.localizedCaseInsensitiveContains("\(number)") {
                extensions.insert(number)
            }
        }

        parseAlterations(from: descriptor).forEach { alterations.insert($0) }
        parseAddTones(from: descriptor).forEach { addTones.insert($0) }

        if quality == .halfDiminished {
            extensions.insert(7)
            alterations.insert(.flat5)
        }

        return Chord(
            rootPitchClass: rootPC,
            bassPitchClass: bassPC,
            quality: quality,
            extensions: extensions,
            alterations: alterations,
            addTones: addTones
        )
    }

    static func parseTextChart(_ text: String) -> [Measure] {
        let normalized = text
            .replacingOccurrences(of: "\n", with: "|")
            .replacingOccurrences(of: "||", with: "|")

        let tokens = normalized
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return tokens.enumerated().map { index, token in
            Measure(index: index, chordSymbol: token, parsedChord: parse(symbol: token))
        }
    }

    private static func parseRootAndDescriptor(from input: String) -> (Int, String)? {
        let nsRange = NSRange(location: 0, length: (input as NSString).length)
        guard let match = rootRegex.firstMatch(in: input, range: nsRange), match.numberOfRanges == 4 else {
            return nil
        }

        let note = (input as NSString).substring(with: match.range(at: 1)).uppercased()
        let accidental = (input as NSString).substring(with: match.range(at: 2))
        let descriptor = (input as NSString).substring(with: match.range(at: 3))

        let rootName = note + accidental
        guard let rootPC = parsePitchClassOnly(rootName) else { return nil }
        return (rootPC, descriptor)
    }

    private static func inferQuality(from descriptor: String) -> ChordQuality {
        let normalized = descriptor.lowercased()

        if normalized.hasPrefix("m7b5") || normalized.hasPrefix("min7b5") || descriptor.contains("ø") {
            return .halfDiminished
        }

        if normalized.hasPrefix("dim") || descriptor.contains("°") || normalized.hasPrefix("o") {
            return .diminished
        }

        if normalized.hasPrefix("aug") || normalized.hasPrefix("+") {
            return .augmented
        }

        if normalized.hasPrefix("sus") || normalized.contains("sus") {
            return .suspended
        }

        if normalized.hasPrefix("m") || normalized.hasPrefix("min") || normalized.hasPrefix("-") {
            return .minor
        }

        if normalized.contains("7") {
            return .dominant
        }

        return .major
    }

    private static func parseAlterations(from descriptor: String) -> Set<ChordAlteration> {
        var result = Set<ChordAlteration>()
        let lower = descriptor.lowercased()

        if lower.contains("b5") { result.insert(.flat5) }
        if lower.contains("#5") { result.insert(.sharp5) }
        if lower.contains("b9") { result.insert(.flat9) }
        if lower.contains("#9") { result.insert(.sharp9) }
        if lower.contains("#11") { result.insert(.sharp11) }
        if lower.contains("b13") { result.insert(.flat13) }

        return result
    }

    private static func parseAddTones(from descriptor: String) -> Set<Int> {
        let lower = descriptor.lowercased()
        var result = Set<Int>()
        if lower.contains("add9") { result.insert(9) }
        if lower.contains("add11") { result.insert(11) }
        if lower.contains("add13") { result.insert(13) }
        return result
    }

    private static func parsePitchClassOnly(_ token: String) -> Int? {
        switch token.lowercased() {
        case "c": return 0
        case "c#", "db": return 1
        case "d": return 2
        case "d#", "eb": return 3
        case "e", "fb": return 4
        case "f", "e#": return 5
        case "f#", "gb": return 6
        case "g": return 7
        case "g#", "ab": return 8
        case "a": return 9
        case "a#", "bb": return 10
        case "b", "cb": return 11
        default: return nil
        }
    }
}
