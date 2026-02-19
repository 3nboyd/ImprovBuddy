import Foundation

struct TheoryEntry: Identifiable, Hashable {
    var id: String
    var chordType: String
    var suggestedScales: [String]
    var arpeggios: [String]
    var guideTones: [String]
    var voiceLeadingTips: [String]
    var drillSuggestionID: String?

    static let curatedMVP: [TheoryEntry] = [
        TheoryEntry(
            id: "maj7",
            chordType: "Maj7",
            suggestedScales: ["Ionian", "Lydian"],
            arpeggios: ["1-3-5-7", "3-5-7-9"],
            guideTones: ["3 and 7"],
            voiceLeadingTips: [
                "Resolve major 7 downward by step when moving to ii.",
                "Use 9 as a color tone and return to 3 on strong beats."
            ],
            drillSuggestionID: "chord_tone_anchors"
        ),
        TheoryEntry(
            id: "min7",
            chordType: "Min7",
            suggestedScales: ["Dorian", "Aeolian"],
            arpeggios: ["1-b3-5-b7", "b3-5-b7-9"],
            guideTones: ["b3 and b7"],
            voiceLeadingTips: [
                "Lead b7 down by half-step into the 3rd of V7.",
                "Target 9 for light color before resolving to b3."
            ],
            drillSuggestionID: "guide_tones_only"
        ),
        TheoryEntry(
            id: "dom7",
            chordType: "Dom7",
            suggestedScales: ["Mixolydian", "Lydian Dominant", "Altered"],
            arpeggios: ["1-3-5-b7", "3-b7-9-13"],
            guideTones: ["3 and b7"],
            voiceLeadingTips: [
                "Resolve 3 to the tonic root or b7 to the tonic 3rd.",
                "Tension tones b9/#9/#11/b13 should resolve by step."
            ],
            drillSuggestionID: "upper_extensions_focus"
        ),
        TheoryEntry(
            id: "m7b5",
            chordType: "m7b5",
            suggestedScales: ["Locrian", "Locrian #2"],
            arpeggios: ["1-b3-b5-b7"],
            guideTones: ["b3 and b7"],
            voiceLeadingTips: [
                "Treat b5 as a tension color and resolve to 5 of V7.",
                "Keep line motion stepwise into altered dominants."
            ],
            drillSuggestionID: "guide_tones_only"
        )
    ]
}
