import Foundation
import SwiftData

@Model
final class Song {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var composer: String?

    var styleTagsData: Data = Data()
    var defaultTempoBPM: Double
    var feel: FeelType
    var timeSignatureTop: Int
    var timeSignatureBottom: Int
    var formData: Data = Data()
    var pdfReferencePath: String?

    var styleTags: [String] {
        get { CodableBlob.decode([String].self, from: styleTagsData, default: []) }
        set { styleTagsData = CodableBlob.encode(newValue) }
    }

    var tags: [String] {
        get { styleTags }
        set { styleTags = Song.normalizedTags(from: newValue) }
    }

    var form: [Measure] {
        get { CodableBlob.decode([Measure].self, from: formData, default: []) }
        set { formData = CodableBlob.encode(newValue) }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        title: String,
        composer: String? = nil,
        styleTags: [String] = [],
        defaultTempoBPM: Double = 120,
        feel: FeelType = .swing,
        timeSignatureTop: Int = 4,
        timeSignatureBottom: Int = 4,
        form: [Measure] = [],
        pdfReferencePath: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.composer = composer
        self.styleTagsData = CodableBlob.encode(styleTags)
        self.defaultTempoBPM = defaultTempoBPM
        self.feel = feel
        self.timeSignatureTop = timeSignatureTop
        self.timeSignatureBottom = timeSignatureBottom
        self.formData = CodableBlob.encode(form)
        self.pdfReferencePath = pdfReferencePath
        self.tags = styleTags
    }

    var flattenedForm: [Measure] {
        form.sorted { $0.index < $1.index }
    }

    func touch() {
        updatedAt = .now
    }

    func hasTag(_ rawTag: String) -> Bool {
        let needle = Song.normalizedTag(rawTag)
        guard !needle.isEmpty else { return false }
        return tags.contains(needle)
    }

    func addTag(_ rawTag: String) {
        let normalized = Song.normalizedTag(rawTag)
        guard !normalized.isEmpty else { return }
        if !hasTag(normalized) {
            tags.append(normalized)
        }
    }

    func removeTag(_ rawTag: String) {
        let normalized = Song.normalizedTag(rawTag)
        guard !normalized.isEmpty else { return }
        tags.removeAll { Song.normalizedTag($0) == normalized }
    }

    func renameTag(from oldRawTag: String, to newRawTag: String) {
        let oldTag = Song.normalizedTag(oldRawTag)
        let newTag = Song.normalizedTag(newRawTag)
        guard !oldTag.isEmpty else { return }
        guard !newTag.isEmpty else {
            removeTag(oldTag)
            return
        }

        var next = tags.map(Song.normalizedTag)
        var changed = false
        for index in next.indices where next[index] == oldTag {
            next[index] = newTag
            changed = true
        }
        if changed {
            tags = next
        }
    }

    static func normalizedTag(_ rawTag: String) -> String {
        rawTag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    static func normalizedTags(from rawTags: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for raw in rawTags {
            let tag = normalizedTag(raw)
            guard !tag.isEmpty, !seen.contains(tag) else { continue }
            seen.insert(tag)
            normalized.append(tag)
        }
        return normalized
    }
}

extension Song {
    static func demoSongs() -> [Song] {
        [
            Song(
                title: "ii-V-I in C",
                composer: "Demo Pack",
                styleTags: ["swing", "study"],
                defaultTempoBPM: 120,
                feel: .swing,
                timeSignatureTop: 4,
                timeSignatureBottom: 4,
                form: [
                    Measure(index: 0, sectionLabel: "A", chordSymbol: "Dm7"),
                    Measure(index: 1, sectionLabel: "A", chordSymbol: "G7"),
                    Measure(index: 2, sectionLabel: "A", chordSymbol: "Cmaj7"),
                    Measure(index: 3, sectionLabel: "A", chordSymbol: "Cmaj7")
                ]
            ),
            Song(
                title: "F Blues",
                composer: "Demo Pack",
                styleTags: ["blues", "swing"],
                defaultTempoBPM: 110,
                feel: .swing,
                timeSignatureTop: 4,
                timeSignatureBottom: 4,
                form: [
                    Measure(index: 0, sectionLabel: "A", chordSymbol: "F7"),
                    Measure(index: 1, sectionLabel: "A", chordSymbol: "Bb7"),
                    Measure(index: 2, sectionLabel: "A", chordSymbol: "F7"),
                    Measure(index: 3, sectionLabel: "A", chordSymbol: "F7"),
                    Measure(index: 4, sectionLabel: "A", chordSymbol: "Bb7"),
                    Measure(index: 5, sectionLabel: "A", chordSymbol: "Bdim7"),
                    Measure(index: 6, sectionLabel: "A", chordSymbol: "F7"),
                    Measure(index: 7, sectionLabel: "A", chordSymbol: "D7"),
                    Measure(index: 8, sectionLabel: "B", chordSymbol: "Gm7"),
                    Measure(index: 9, sectionLabel: "B", chordSymbol: "C7"),
                    Measure(index: 10, sectionLabel: "B", chordSymbol: "F7"),
                    Measure(index: 11, sectionLabel: "B", chordSymbol: "C7")
                ]
            ),
            Song(
                title: "Rhythm Changes (Simple)",
                composer: "Demo Pack",
                styleTags: ["rhythm changes", "bebop"],
                defaultTempoBPM: 140,
                feel: .swing,
                timeSignatureTop: 4,
                timeSignatureBottom: 4,
                form: [
                    Measure(index: 0, sectionLabel: "A", chordSymbol: "Bbmaj7"),
                    Measure(index: 1, sectionLabel: "A", chordSymbol: "G7"),
                    Measure(index: 2, sectionLabel: "A", chordSymbol: "Cm7"),
                    Measure(index: 3, sectionLabel: "A", chordSymbol: "F7"),
                    Measure(index: 4, sectionLabel: "B", chordSymbol: "D7"),
                    Measure(index: 5, sectionLabel: "B", chordSymbol: "G7"),
                    Measure(index: 6, sectionLabel: "B", chordSymbol: "C7"),
                    Measure(index: 7, sectionLabel: "B", chordSymbol: "F7")
                ]
            )
        ]
    }
}
