import Foundation
import SwiftData

enum LibraryItemType: String, Codable, CaseIterable, Identifiable {
    case ideaSnippet
    case lickCard
    case theoryFavorite

    var id: String { rawValue }
}

@Model
final class LibraryItem {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var type: LibraryItemType
    var title: String
    var notes: String

    var tagsData: Data = Data()

    var audioFilePath: String?
    var midiFilePath: String?
    var keyCenter: String?
    var tempoBPM: Double?

    var loopStart: Double?
    var loopEnd: Double?
    var transposeSemitones: Int?

    var theoryIdentifier: String?
    var recorderMetronomeReferenceData: Data = Data()

    var tags: [String] {
        get { CodableBlob.decode([String].self, from: tagsData, default: []) }
        set { tagsData = CodableBlob.encode(newValue) }
    }

    var recorderMetronomeReference: RecorderMetronomeReference? {
        get { CodableBlob.decode(RecorderMetronomeReference?.self, from: recorderMetronomeReferenceData, default: nil) }
        set { recorderMetronomeReferenceData = CodableBlob.encode(newValue) }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        type: LibraryItemType,
        title: String,
        notes: String = "",
        tags: [String] = [],
        audioFilePath: String? = nil,
        midiFilePath: String? = nil,
        keyCenter: String? = nil,
        tempoBPM: Double? = nil,
        loopStart: Double? = nil,
        loopEnd: Double? = nil,
        transposeSemitones: Int? = nil,
        theoryIdentifier: String? = nil,
        recorderMetronomeReference: RecorderMetronomeReference? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.type = type
        self.title = title
        self.notes = notes
        self.tagsData = CodableBlob.encode(tags)
        self.audioFilePath = audioFilePath
        self.midiFilePath = midiFilePath
        self.keyCenter = keyCenter
        self.tempoBPM = tempoBPM
        self.loopStart = loopStart
        self.loopEnd = loopEnd
        self.transposeSemitones = transposeSemitones
        self.theoryIdentifier = theoryIdentifier
        self.recorderMetronomeReferenceData = CodableBlob.encode(recorderMetronomeReference)
    }
}

private enum RecorderItemTag {
    static let deleted = "__jade_recorder_deleted"
    static let pinned = "__jade_recorder_pinned"
}

extension LibraryItem {
    var isRecorderDeleted: Bool {
        get { hasRecorderTag(RecorderItemTag.deleted) }
        set { setRecorderTag(RecorderItemTag.deleted, enabled: newValue) }
    }

    var isRecorderPinned: Bool {
        get { hasRecorderTag(RecorderItemTag.pinned) }
        set { setRecorderTag(RecorderItemTag.pinned, enabled: newValue) }
    }

    private func hasRecorderTag(_ tag: String) -> Bool {
        let needle = normalizedTag(tag)
        return tags.contains(where: { normalizedTag($0) == needle })
    }

    private func setRecorderTag(_ tag: String, enabled: Bool) {
        let needle = normalizedTag(tag)
        var next = tags.filter { normalizedTag($0) != needle }
        if enabled {
            next.append(tag)
        }
        tags = next
    }

    private func normalizedTag(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
