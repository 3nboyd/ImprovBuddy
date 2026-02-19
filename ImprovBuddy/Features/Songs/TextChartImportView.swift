import SwiftUI

struct TextChartImportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var chartText = ""
    let onImport: ([Measure]) -> Void

    var previewMeasures: [Measure] {
        ChordParser.parseTextChart(chartText)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextEditor(text: $chartText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                    .padding(8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.quaternary)
                    }

                Text("Use `|` or new lines to split measures. Example: `Dm7 | G7 | Cmaj7 | Cmaj7`")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                List(previewMeasures) { measure in
                    HStack {
                        Text("\(measure.index + 1)")
                            .frame(width: 30, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(measure.chordSymbol)
                        Spacer()
                        if measure.parsedChord == nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Import Text Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(previewMeasures)
                        dismiss()
                    }
                    .disabled(previewMeasures.isEmpty)
                }
            }
        }
    }
}
