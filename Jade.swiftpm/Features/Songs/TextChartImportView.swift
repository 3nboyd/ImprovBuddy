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
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button("Import") {
                        onImport(previewMeasures)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(previewMeasures.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider().opacity(0.2)
                }
            }
        }
    }
}
