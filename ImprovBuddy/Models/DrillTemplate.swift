import Foundation

struct DrillTemplate: Identifiable, Codable, Hashable {
    struct Configuration: Codable, Hashable {
        var durationInMeasures: Int
        var constraints: [String]
    }

    var id: String
    var title: String
    var description: String
    var configuration: Configuration

    static let mvpTemplates: [DrillTemplate] = [
        DrillTemplate(
            id: "guide_tones_only",
            title: "Guide Tones Only",
            description: "Play only 3rds and 7ths through the form.",
            configuration: .init(durationInMeasures: 16, constraints: ["only_3rd_7th"])
        ),
        DrillTemplate(
            id: "chord_tone_anchors",
            title: "Chord Tone Anchors",
            description: "Land on chord tones on beats 1 and 3 in each measure.",
            configuration: .init(durationInMeasures: 16, constraints: ["beats_1_3_chord_tones"])
        ),
        DrillTemplate(
            id: "upper_extensions_focus",
            title: "Upper Extensions Focus",
            description: "Target 9 and 13 on dominant chords and resolve clearly.",
            configuration: .init(durationInMeasures: 16, constraints: ["dom9_13_focus"])
        ),
        DrillTemplate(
            id: "rhythm_only_chorus",
            title: "Rhythm-only Chorus",
            description: "Use one pitch only and maximize rhythmic variety.",
            configuration: .init(durationInMeasures: 16, constraints: ["single_pitch"])
        ),
        DrillTemplate(
            id: "lay_back_drill",
            title: "Lay Back Drill",
            description: "Aim slightly behind the beat while staying consistent.",
            configuration: .init(durationInMeasures: 12, constraints: ["behind_beat_target"])
        )
    ]
}
