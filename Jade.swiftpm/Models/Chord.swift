import Foundation

enum ChordQuality: String, Codable, CaseIterable {
    case major
    case minor
    case dominant
    case diminished
    case halfDiminished
    case suspended
    case augmented
}

enum ChordAlteration: String, Codable, CaseIterable, Hashable {
    case flat5
    case sharp5
    case flat9
    case sharp9
    case sharp11
    case flat13
}

struct Chord: Codable, Hashable {
    var rootPitchClass: Int
    var bassPitchClass: Int?
    var quality: ChordQuality
    var extensions: Set<Int>
    var alterations: Set<ChordAlteration>
    var addTones: Set<Int>

    init(
        rootPitchClass: Int,
        bassPitchClass: Int? = nil,
        quality: ChordQuality,
        extensions: Set<Int> = [],
        alterations: Set<ChordAlteration> = [],
        addTones: Set<Int> = []
    ) {
        self.rootPitchClass = Chord.normalizePitchClass(rootPitchClass)
        self.bassPitchClass = bassPitchClass.map(Chord.normalizePitchClass)
        self.quality = quality
        self.extensions = extensions
        self.alterations = alterations
        self.addTones = addTones
    }

    static func normalizePitchClass(_ value: Int) -> Int {
        let normalized = value % 12
        return normalized < 0 ? normalized + 12 : normalized
    }

    var nameRoot: String {
        Self.pitchClassNames[rootPitchClass]
    }

    func chordTonePitchClasses() -> Set<Int> {
        let intervals = coreChordIntervals()
        return Set(intervals.map { Self.normalizePitchClass(rootPitchClass + $0) })
    }

    func extensionPitchClasses() -> Set<Int> {
        var result = Set<Int>()
        for ext in extensions {
            if let interval = Self.intervalForExtension(ext) {
                result.insert(Self.normalizePitchClass(rootPitchClass + interval))
            }
        }

        for add in addTones {
            if let interval = Self.intervalForExtension(add) {
                result.insert(Self.normalizePitchClass(rootPitchClass + interval))
            }
        }

        for alt in alterations {
            let interval: Int
            switch alt {
            case .flat5: interval = 6
            case .sharp5: interval = 8
            case .flat9: interval = 13
            case .sharp9: interval = 15
            case .sharp11: interval = 18
            case .flat13: interval = 20
            }
            result.insert(Self.normalizePitchClass(rootPitchClass + interval))
        }

        return result.subtracting(chordTonePitchClasses())
    }

    func suggestedScalePitchClasses() -> Set<Int> {
        let root = rootPitchClass
        let intervals: [Int]
        switch quality {
        case .major:
            if extensions.contains(7) || extensions.contains(9) || extensions.contains(13) {
                intervals = [0, 2, 4, 5, 7, 9, 11]
            } else {
                intervals = [0, 2, 4, 5, 7, 9, 11]
            }
        case .minor:
            intervals = [0, 2, 3, 5, 7, 9, 10]
        case .dominant:
            if alterations.isEmpty {
                intervals = [0, 2, 4, 5, 7, 9, 10]
            } else {
                intervals = [0, 1, 3, 4, 6, 8, 10]
            }
        case .diminished:
            intervals = [0, 2, 3, 5, 6, 8, 9, 11]
        case .halfDiminished:
            intervals = [0, 2, 3, 5, 6, 8, 10]
        case .suspended:
            intervals = [0, 2, 5, 7, 9, 10]
        case .augmented:
            intervals = [0, 2, 4, 6, 8, 10]
        }

        return Set(intervals.map { Self.normalizePitchClass(root + $0) })
    }

    private func coreChordIntervals() -> [Int] {
        var intervals: [Int]

        switch quality {
        case .major:
            intervals = [0, 4, 7]
        case .minor:
            intervals = [0, 3, 7]
        case .dominant:
            intervals = [0, 4, 7]
        case .diminished:
            intervals = [0, 3, 6]
        case .halfDiminished:
            intervals = [0, 3, 6]
        case .suspended:
            intervals = [0, 5, 7]
        case .augmented:
            intervals = [0, 4, 8]
        }

        let hasExplicit7 = extensions.contains(7) || extensions.contains(9) || extensions.contains(11) || extensions.contains(13)
        if hasExplicit7 {
            let seventhInterval: Int
            switch quality {
            case .major:
                seventhInterval = 11
            case .dominant, .minor, .halfDiminished, .suspended, .augmented:
                seventhInterval = 10
            case .diminished:
                seventhInterval = 9
            }
            intervals.append(seventhInterval)
        }

        if alterations.contains(.flat5) {
            if let idx = intervals.firstIndex(of: 7) { intervals[idx] = 6 }
        }

        if alterations.contains(.sharp5) {
            if let idx = intervals.firstIndex(of: 7) { intervals[idx] = 8 }
        }

        return intervals
    }

    static func intervalForExtension(_ extensionNumber: Int) -> Int? {
        switch extensionNumber {
        case 2, 9:
            return 14
        case 4, 11:
            return 17
        case 6, 13:
            return 21
        case 7:
            return 10
        default:
            return nil
        }
    }

    static let pitchClassNames = [
        "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"
    ]
}
