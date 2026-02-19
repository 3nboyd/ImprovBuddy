import SwiftUI

struct LiveSessionView: View {
    @ObservedObject var engine: CoachSessionEngine

    let onPauseResume: () -> Void
    let onEnd: () -> Void
    let onJumpToBar: (Int) -> Void
    let onRestartChorus: () -> Void

    @State private var jumpBarText = "1"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        MetricTile(
                            title: "Target BPM",
                            value: String(format: "%.0f", engine.targetTempoBPM),
                            subtitle: String(format: "live %.1f", engine.liveEstimatedBPM)
                        )
                        MetricTile(
                            title: "Timing Err",
                            value: String(format: "%.0f ms", engine.latestTimingErrorMs),
                            subtitle: engine.tempoDriftState == .stable ? "stable" : "drifting"
                        )
                        MetricTile(title: "Pocket", value: engine.pocketState.rawValue.capitalized, subtitle: "ahead/behind")
                        MetricTile(
                            title: "Swing",
                            value: engine.swingRatio > 0 ? String(format: "%.2f", engine.swingRatio) : "n/a",
                            subtitle: "ratio"
                        )
                        MetricTile(title: "Harmony", value: engine.harmonyState.displayName, subtitle: "live")
                        MetricTile(
                            title: "Form",
                            value: "M\(engine.currentMeasureIndex + 1)",
                            subtitle: "\(engine.currentSectionLabel) • \(engine.currentChordSymbol)"
                        )
                    }

                    Text(engine.coachPrompt)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            Button(engine.isPaused ? "Resume" : "Pause") {
                                onPauseResume()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                            Button("Restart Chorus") {
                                onRestartChorus()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }

                        VStack(spacing: 10) {
                            Button(engine.isPaused ? "Resume" : "Pause") {
                                onPauseResume()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                            Button("Restart Chorus") {
                                onRestartChorus()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                    }

                    HStack(spacing: 12) {
                        TextField("Bar", text: $jumpBarText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)

                        Button("Jump to Bar") {
                            let bar = Int(jumpBarText) ?? 1
                            onJumpToBar(max(1, bar))
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) {
                    onEnd()
                } label: {
                    Text("End Session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.top, 8)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Live Coach")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
