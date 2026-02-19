import Foundation

struct Measure: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var index: Int
    var sectionLabel: String?
    var chordSymbol: String
    var parsedChord: Chord?
    var rehearsalMark: String?

    init(
        index: Int,
        sectionLabel: String? = nil,
        chordSymbol: String,
        parsedChord: Chord? = nil,
        rehearsalMark: String? = nil
    ) {
        self.index = index
        self.sectionLabel = sectionLabel
        self.chordSymbol = chordSymbol
        self.parsedChord = parsedChord
        self.rehearsalMark = rehearsalMark
    }
}
