import Foundation
import SwiftData

enum SongAttachmentKind: String, Codable {
    case pdf
    case image
}

struct SongAttachment: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: SongAttachmentKind
    var path: String
    var originalFileName: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: SongAttachmentKind,
        path: String,
        originalFileName: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.originalFileName = originalFileName
        self.createdAt = createdAt
    }

    var resolvedURL: URL? {
        if let url = URL(string: path), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: path)
    }

    static func inferredFileName(from path: String) -> String {
        if let url = URL(string: path), url.scheme != nil {
            return url.lastPathComponent
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

@Model
final class Song {
    static let defaultTagSuggestions: [String] = [
        "practice",
        "jazz",
        "big band",
        "standards",
        "misc"
    ]

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
    var attachmentsData: Data = Data()

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

    var attachments: [SongAttachment] {
        get { CodableBlob.decode([SongAttachment].self, from: attachmentsData, default: []) }
        set {
            attachmentsData = CodableBlob.encode(newValue)
            if let firstPDF = newValue.first(where: { $0.kind == .pdf }) {
                pdfReferencePath = firstPDF.path
            } else if let first = newValue.first {
                pdfReferencePath = first.path
            } else {
                pdfReferencePath = nil
            }
        }
    }

    var mediaAttachments: [SongAttachment] {
        let items = attachments
        if !items.isEmpty {
            return items
        }

        guard let legacyPath = pdfReferencePath, !legacyPath.isEmpty else {
            return []
        }

        return [
            SongAttachment(
                kind: .pdf,
                path: legacyPath,
                originalFileName: SongAttachment.inferredFileName(from: legacyPath)
            )
        ]
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
        pdfReferencePath: String? = nil,
        attachments: [SongAttachment] = []
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
        self.attachmentsData = CodableBlob.encode(attachments)
        if let firstPDF = attachments.first(where: { $0.kind == .pdf }) {
            self.pdfReferencePath = firstPDF.path
        } else if let first = attachments.first {
            self.pdfReferencePath = first.path
        }
        self.tags = styleTags
    }

    var flattenedForm: [Measure] {
        form.sorted { $0.index < $1.index }
    }

    func touch() {
        updatedAt = .now
    }

    @discardableResult
    func migrateLegacyPDFReferenceIfNeeded() -> Bool {
        guard attachments.isEmpty, let legacyPath = pdfReferencePath, !legacyPath.isEmpty else {
            return false
        }

        attachments = [
            SongAttachment(
                kind: .pdf,
                path: legacyPath,
                originalFileName: SongAttachment.inferredFileName(from: legacyPath)
            )
        ]
        return true
    }

    func addAttachments(_ newAttachments: [SongAttachment]) {
        guard !newAttachments.isEmpty else { return }

        var next = attachments
        var seen = Set(next.map(\.path))
        for attachment in newAttachments where !seen.contains(attachment.path) {
            next.append(attachment)
            seen.insert(attachment.path)
        }
        attachments = next
    }

    func removeAttachment(id: UUID) {
        var next = attachments
        next.removeAll { $0.id == id }
        attachments = next
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
                title: "Twinkle Twinkle Little Star (example)",
                composer: nil,
                styleTags: ["practice", "standards"],
                defaultTempoBPM: 88,
                feel: .straight,
                timeSignatureTop: 4,
                timeSignatureBottom: 4,
                form: []
            ),
            Song(
                title: "Ode to Joy (example)",
                composer: nil,
                styleTags: ["practice", "misc"],
                defaultTempoBPM: 92,
                feel: .straight,
                timeSignatureTop: 4,
                timeSignatureBottom: 4,
                form: []
            ),
            Song(
                title: "When the Saints Go Marching In (example)",
                composer: nil,
                styleTags: ["practice", "jazz"],
                defaultTempoBPM: 104,
                feel: .swing,
                timeSignatureTop: 4,
                timeSignatureBottom: 4,
                form: []
            )
        ]
    }
}
