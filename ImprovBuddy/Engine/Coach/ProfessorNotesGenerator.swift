import Foundation

struct ProfessorReportSections {
    var strengths: [String]
    var opportunities: [String]
    var nextDrills: [DrillTemplate]

    var fullText: String {
        let strengthsText = strengths.joined(separator: "\n")
        let opportunitiesText = opportunities.joined(separator: "\n")
        let drillsText = nextDrills.map(\.title).joined(separator: ", ")
        return "Strengths:\n\(strengthsText)\n\nOpportunities:\n\(opportunitiesText)\n\nNext Drills:\n\(drillsText)"
    }
}

struct ProfessorNotesGenerator {
    static func generate(summary: SessionSummaryMetrics) -> ProfessorReportSections {
        var strengths: [String] = []
        var opportunities: [String] = []
        var drillIDs: [String] = []

        if summary.tempoDrift.meanAbsoluteErrorMs <= 18 {
            strengths.append("Your pulse stayed stable with low average timing error. The line breathes naturally against the grid.")
        }

        if abs(summary.tempoDrift.signedBiasMs) <= 8 {
            strengths.append("Pocket placement stayed centered and balanced. You are not consistently rushing or dragging.")
        }

        if summary.harmony.downbeatChordTonePct >= 0.65 {
            strengths.append("Strong harmonic landing on downbeats. Your phrase endings outline the form clearly.")
        }

        if summary.harmony.resolutionRate >= 0.6 {
            strengths.append("Outside notes usually resolve with intention. Tension and release feels coherent.")
        }

        if strengths.isEmpty {
            strengths.append("You maintained enough continuity to complete full choruses and keep the form moving.")
            strengths.append("There are clear moments of intention in both rhythm and note choice to build on.")
        }

        if summary.harmony.downbeatChordTonePct < 0.5 {
            opportunities.append("Downbeat guide-tone clarity is the biggest upgrade path. Prioritize landing 3rds and 7ths at changes.")
            drillIDs.append("guide_tones_only")
        }

        if summary.harmony.rootOverusePct > 0.4 {
            opportunities.append("Root notes are overrepresented. Increase upper-structure targets to make harmonic motion clearer.")
            drillIDs.append("chord_tone_anchors")
        }

        if summary.swing.consistencyStdDev > 0.45 {
            opportunities.append("Swing ratio varies a lot phrase to phrase. Work on consistent long-short placement for cleaner groove.")
            drillIDs.append("rhythm_only_chorus")
        }

        if summary.tempoDrift.driftSlope > 0.2 || summary.tempoDrift.meanAbsoluteErrorMs > 25 {
            opportunities.append("Timing drift increases under density. Practice reducing note density while preserving phrase shape.")
            drillIDs.append("lay_back_drill")
        }

        if summary.harmony.resolutionRate < 0.45 {
            opportunities.append("Tension tones need clearer resolution. Resolve outside tones into nearby chord tones within one beat.")
            drillIDs.append("upper_extensions_focus")
        }

        if opportunities.isEmpty {
            opportunities.append("Current metrics are balanced. Next gains will come from deliberate motif development across sections.")
            opportunities.append("Push dynamic contrast while preserving your current pocket stability.")
        }

        var drillTemplates: [DrillTemplate] = []
        for id in drillIDs {
            if let template = DrillTemplate.mvpTemplates.first(where: { $0.id == id }), !drillTemplates.contains(template) {
                drillTemplates.append(template)
            }
        }

        if drillTemplates.count < 2 {
            for fallback in DrillTemplate.mvpTemplates {
                if !drillTemplates.contains(fallback) {
                    drillTemplates.append(fallback)
                }
                if drillTemplates.count == 2 { break }
            }
        }

        return ProfessorReportSections(
            strengths: Array(strengths.prefix(3)),
            opportunities: Array(opportunities.prefix(3)),
            nextDrills: Array(drillTemplates.prefix(2))
        )
    }
}
