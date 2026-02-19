import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SongEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let song: Song?

    @State private var title = ""
    @State private var composer = ""
    @State private var styleTagsText = ""
    @State private var defaultTempoBPM = 120.0
    @State private var feel: FeelType = .swing
    @State private var timeSignatureTop = 4
    @State private var timeSignatureBottom = 4
    @State private var measures: [EditableMeasure] = []

    @State private var showingTextImport = false
    @State private var showingPDFPicker = false
    @State private var showingPDFPreview = false
    @State private var pdfReferencePath: String?

    @State private var parseErrors: [Int] = []

    init(song: Song?) {
        self.song = song
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Song") {
                    TextField("Title", text: $title)
                    TextField("Composer", text: $composer)
                    TextField("Style tags (comma separated)", text: $styleTagsText)
                }

                Section("Defaults") {
                    HStack {
                        Slider(value: $defaultTempoBPM, in: 40...320, step: 1)
                        Text("\(Int(defaultTempoBPM))")
                            .monospacedDigit()
                    }

                    Picker("Feel", selection: $feel) {
                        ForEach(FeelType.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Stepper("Top: \(timeSignatureTop)", value: $timeSignatureTop, in: 2...12)
                        Stepper("Bottom: \(timeSignatureBottom)", value: $timeSignatureBottom, in: 2...8)
                    }
                }

                Section("Chord Form") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("Import Text Chart") {
                                showingTextImport = true
                            }

                            Button("Add Measure") {
                                let nextIndex = measures.count
                                measures.append(EditableMeasure(index: nextIndex, sectionLabel: nil, chordSymbol: "Cmaj7", rehearsalMark: nil))
                            }
                        }

                        if !parseErrors.isEmpty {
                            Text("Chord parse warning in measures: \(parseErrors.map { String($0 + 1) }.joined(separator: ", ")).")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }

                    ForEach($measures) { $measure in
                        HStack(alignment: .top) {
                            Text("\(measure.index + 1)")
                                .frame(width: 30, alignment: .leading)
                                .foregroundStyle(.secondary)

                            TextField("Section", text: Binding(
                                get: { measure.sectionLabel ?? "" },
                                set: { measure.sectionLabel = $0.isEmpty ? nil : $0 }
                            ))
                            .frame(width: 70)

                            TextField("Chord", text: $measure.chordSymbol)
                                .textInputAutocapitalization(.characters)

                            TextField("Mark", text: Binding(
                                get: { measure.rehearsalMark ?? "" },
                                set: { measure.rehearsalMark = $0.isEmpty ? nil : $0 }
                            ))
                            .frame(width: 80)

                            Button(role: .destructive) {
                                deleteMeasure(id: measure.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .font(.callout)
                    }
                }

                Section("PDF Reference") {
                    if let pdfReferencePath,
                       let url = URL(string: pdfReferencePath) {
                        Text(url.lastPathComponent)
                            .font(.subheadline)
                        HStack {
                            Button("Preview") {
                                showingPDFPreview = true
                            }
                            Button("Remove", role: .destructive) {
                                self.pdfReferencePath = nil
                            }
                        }
                    }

                    Button("Import PDF Reference") {
                        showingPDFPicker = true
                    }
                }
            }
            .navigationTitle(song == nil ? "New Song" : "Edit Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveSong() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || measures.isEmpty)
                }
            }
            .sheet(isPresented: $showingTextImport) {
                TextChartImportView { imported in
                    measures = imported.enumerated().map { index, measure in
                        EditableMeasure(
                            id: measure.id,
                            index: index,
                            sectionLabel: measure.sectionLabel,
                            chordSymbol: measure.chordSymbol,
                            rehearsalMark: measure.rehearsalMark
                        )
                    }
                    validateChords()
                }
            }
            .sheet(isPresented: $showingPDFPreview) {
                if let pdfReferencePath,
                   let url = URL(string: pdfReferencePath) {
                    PDFReferenceView(url: url)
                } else {
                    Text("No PDF selected")
                        .padding()
                }
            }
            .fileImporter(
                isPresented: $showingPDFPicker,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handlePDFImport(result)
            }
            .onAppear(perform: loadData)
            .onChange(of: measures, initial: false) { _, _ in
                validateChords()
            }
        }
    }

    private func loadData() {
        guard let song else {
            if measures.isEmpty {
                measures = [EditableMeasure(index: 0, sectionLabel: "A", chordSymbol: "Cmaj7", rehearsalMark: nil)]
            }
            return
        }

        title = song.title
        composer = song.composer ?? ""
        styleTagsText = song.styleTags.joined(separator: ", ")
        defaultTempoBPM = song.defaultTempoBPM
        feel = song.feel
        timeSignatureTop = song.timeSignatureTop
        timeSignatureBottom = song.timeSignatureBottom
        pdfReferencePath = song.pdfReferencePath

        measures = song.form.sorted { $0.index < $1.index }.map {
            EditableMeasure(
                id: $0.id,
                index: $0.index,
                sectionLabel: $0.sectionLabel,
                chordSymbol: $0.chordSymbol,
                rehearsalMark: $0.rehearsalMark
            )
        }

        if measures.isEmpty {
            measures = [EditableMeasure(index: 0, sectionLabel: "A", chordSymbol: "Cmaj7", rehearsalMark: nil)]
        }

        validateChords()
    }

    private func saveSong() {
        let normalizedMeasures = measures.enumerated().map { offset, measure in
            Measure(
                index: offset,
                sectionLabel: measure.sectionLabel,
                chordSymbol: measure.chordSymbol,
                parsedChord: ChordParser.parse(symbol: measure.chordSymbol),
                rehearsalMark: measure.rehearsalMark
            )
        }

        let parsedTags = styleTagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let song {
            song.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            song.composer = composer.isEmpty ? nil : composer
            song.styleTags = parsedTags
            song.defaultTempoBPM = defaultTempoBPM
            song.feel = feel
            song.timeSignatureTop = timeSignatureTop
            song.timeSignatureBottom = timeSignatureBottom
            song.form = normalizedMeasures
            song.pdfReferencePath = pdfReferencePath
            song.touch()
        } else {
            let newSong = Song(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                composer: composer.isEmpty ? nil : composer,
                styleTags: parsedTags,
                defaultTempoBPM: defaultTempoBPM,
                feel: feel,
                timeSignatureTop: timeSignatureTop,
                timeSignatureBottom: timeSignatureBottom,
                form: normalizedMeasures,
                pdfReferencePath: pdfReferencePath
            )
            modelContext.insert(newSong)
        }

        try? modelContext.save()
        dismiss()
    }

    private func deleteMeasure(id: UUID) {
        measures.removeAll { $0.id == id }
        for (index, _) in measures.enumerated() {
            measures[index].index = index
        }
        validateChords()
    }

    private func validateChords() {
        parseErrors = measures
            .enumerated()
            .compactMap { index, measure in
                ChordParser.parse(symbol: measure.chordSymbol) == nil ? index : nil
            }
    }

    private func handlePDFImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let source = urls.first else { return }

        let destinationFolder = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SongPDFs", isDirectory: true)

        guard let destinationFolder else { return }

        do {
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            let destination = destinationFolder.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")

            _ = source.startAccessingSecurityScopedResource()
            defer { source.stopAccessingSecurityScopedResource() }

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.copyItem(at: source, to: destination)
            pdfReferencePath = destination.absoluteString
        } catch {
            print("PDF import failed: \(error)")
        }
    }
}

private struct EditableMeasure: Identifiable, Equatable {
    var id: UUID = UUID()
    var index: Int
    var sectionLabel: String?
    var chordSymbol: String
    var rehearsalMark: String?
}

private struct PDFReferenceView: View {
    let url: URL

    var body: some View {
        PDFKitRepresentable(url: url)
            .ignoresSafeArea(edges: .bottom)
    }
}

private struct PDFKitRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
    }
}
