import Charts
import SwiftUI

private enum ReportTab: String, CaseIterable, Identifiable {
    case groove = "Groove"
    case harmony = "Harmony"
    case notes = "Professor Notes"
    case drills = "Recommended Drills"

    var id: String { rawValue }
}

struct SessionReportView: View {
    let session: PracticeSession
    let report: ProfessorReportSections

    @State private var tab: ReportTab = .groove

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Section", selection: $tab) {
                    ForEach(ReportTab.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ScrollView {
                    switch tab {
                    case .groove:
                        grooveView
                    case .harmony:
                        harmonyView
                    case .notes:
                        notesView
                    case .drills:
                        drillsView
                    }
                }
            }
            .navigationTitle("Professor Report")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var grooveView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tempo Drift")
                .font(.headline)

            Chart(session.estimatedBPMOverTime, id: \.time) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("BPM", point.value)
                )
                .foregroundStyle(.blue)
            }
            .frame(height: 180)

            Text("Timing Error (ms)")
                .font(.headline)

            Chart(session.timingErrorOverTimeMs, id: \.time) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Error", point.value)
                )
                .foregroundStyle(.orange)
            }
            .frame(height: 180)

            if !session.swingRatioOverTime.isEmpty {
                Text("Swing Ratio")
                    .font(.headline)

                Chart(session.swingRatioOverTime, id: \.time) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("Ratio", point.value)
                    )
                    .foregroundStyle(.purple)
                }
                .frame(height: 180)
            }

            Text("Summary")
                .font(.headline)
            Text("Mean abs timing error: \(String(format: "%.1f", session.summary.tempoDrift.meanAbsoluteErrorMs)) ms")
            Text("Pocket bias: \(String(format: "%.1f", session.summary.pocket.meanBiasMs)) ms")
            Text("Stability score: \(String(format: "%.2f", session.summary.tempoDrift.stabilityScore))")
        }
        .padding()
    }

    private var harmonyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            let h = session.summary.harmony
            Text("Harmony Breakdown")
                .font(.headline)

            Chart {
                SectorMark(angle: .value("Chord Tone", h.chordTonePct), innerRadius: .ratio(0.5))
                    .foregroundStyle(.green)
                SectorMark(angle: .value("Extension", h.extensionPct), innerRadius: .ratio(0.5))
                    .foregroundStyle(.blue)
                SectorMark(angle: .value("Approach", h.approachPct), innerRadius: .ratio(0.5))
                    .foregroundStyle(.yellow)
                SectorMark(angle: .value("Outside", h.outsidePct), innerRadius: .ratio(0.5))
                    .foregroundStyle(.red)
            }
            .frame(height: 220)

            Text("Downbeat chord-tone accuracy: \(String(format: "%.0f%%", h.downbeatChordTonePct * 100))")
            Text("Resolution rate: \(String(format: "%.0f%%", h.resolutionRate * 100))")
            Text("Root usage: \(String(format: "%.0f%%", h.rootOverusePct * 100))")

            Text("Density Map")
                .font(.headline)

            Chart(noteDensityByMeasure(), id: \.measure) { entry in
                BarMark(
                    x: .value("Measure", entry.measure),
                    y: .value("Notes", entry.count)
                )
                .foregroundStyle(.teal)
            }
            .frame(height: 180)
        }
        .padding()
    }

    private var notesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Strengths")
                .font(.headline)
            ForEach(report.strengths, id: \.self) { line in
                Text(line)
            }

            Text("Opportunities")
                .font(.headline)
                .padding(.top, 8)
            ForEach(report.opportunities, id: \.self) { line in
                Text(line)
            }
        }
        .padding()
    }

    private var drillsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(report.nextDrills) { drill in
                VStack(alignment: .leading, spacing: 6) {
                    Text(drill.title)
                        .font(.headline)
                    Text(drill.description)
                        .font(.subheadline)
                    Text("Duration: \(drill.configuration.durationInMeasures) measures")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Constraints: \(drill.configuration.constraints.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }

    private func noteDensityByMeasure() -> [(measure: Int, count: Int)] {
        let measureDuration = (60 / session.targetTempoBPM) * Double(session.timeSignatureTop)
        guard measureDuration > 0 else { return [] }

        var buckets: [Int: Int] = [:]
        for note in session.detectedPitchOverTime {
            let measure = Int(note.time / measureDuration) + 1
            buckets[measure, default: 0] += 1
        }

        return buckets.keys.sorted().map { ($0, buckets[$0, default: 0]) }
    }
}
