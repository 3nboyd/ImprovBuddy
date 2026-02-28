import SwiftData
import SwiftUI

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
    @State private var attachments: [SongAttachment] = []

    @State private var showingMediaPicker = false
    @State private var mediaImportMessage = ""

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

                Section("Sheet Music") {
                    if attachments.isEmpty {
                        Text("No files attached")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(attachments) { attachment in
                            HStack(spacing: 10) {
                                Image(systemName: attachment.kind == .pdf ? "doc.richtext" : "photo")
                                    .foregroundStyle(.secondary)
                                Text(attachment.originalFileName)
                                    .lineLimit(1)
                                Spacer()
                                Button(role: .destructive) {
                                    removeAttachment(id: attachment.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Button {
                        showingMediaPicker = true
                    } label: {
                        Label("Add Files", systemImage: "paperclip")
                    }

                    if !mediaImportMessage.isEmpty {
                        Text(mediaImportMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(song == nil ? "New Song" : "Edit Song")
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

                    Button("Save") {
                        saveSong()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider().opacity(0.2)
                }
            }
            .fileImporter(
                isPresented: $showingMediaPicker,
                allowedContentTypes: SongMediaStorage.allowedImportTypes,
                allowsMultipleSelection: true
            ) { result in
                handleMediaImport(result)
            }
            .onAppear(perform: loadData)
        }
    }

    private func loadData() {
        guard let song else {
            return
        }

        title = song.title
        composer = song.composer ?? ""
        styleTagsText = song.tags.joined(separator: ", ")
        defaultTempoBPM = song.defaultTempoBPM
        feel = song.feel
        timeSignatureTop = song.timeSignatureTop
        timeSignatureBottom = song.timeSignatureBottom

        if song.migrateLegacyPDFReferenceIfNeeded() {
            song.touch()
            try? modelContext.save()
        }
        attachments = song.mediaAttachments
    }

    private func saveSong() {
        let parsedTags = Song.normalizedTags(from: styleTagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedComposer = composer.trimmingCharacters(in: .whitespacesAndNewlines)

        if let song {
            song.title = trimmedTitle
            song.composer = normalizedComposer.isEmpty ? nil : normalizedComposer
            song.tags = parsedTags
            song.defaultTempoBPM = defaultTempoBPM
            song.feel = feel
            song.timeSignatureTop = timeSignatureTop
            song.timeSignatureBottom = timeSignatureBottom
            song.form = []
            song.attachments = attachments
            song.touch()
        } else {
            let newSong = Song(
                title: trimmedTitle,
                composer: normalizedComposer.isEmpty ? nil : normalizedComposer,
                styleTags: parsedTags,
                defaultTempoBPM: defaultTempoBPM,
                feel: feel,
                timeSignatureTop: timeSignatureTop,
                timeSignatureBottom: timeSignatureBottom,
                form: [],
                attachments: attachments
            )
            modelContext.insert(newSong)
        }

        try? modelContext.save()
        dismiss()
    }

    private func handleMediaImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, !urls.isEmpty else { return }

        let securedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for securedURL in securedURLs {
                securedURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let imported = try SongMediaStorage.copyAttachments(from: urls)
            guard !imported.isEmpty else {
                mediaImportMessage = "No supported files selected."
                return
            }

            var existingPaths = Set(attachments.map(\.path))
            for attachment in imported where !existingPaths.contains(attachment.path) {
                attachments.append(attachment)
                existingPaths.insert(attachment.path)
            }

            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if
                    let firstPDF = imported.first(where: { $0.kind == .pdf }),
                    let pdfURL = firstPDF.resolvedURL
                {
                    let metadata = PDFSongMetadataExtractor.extract(from: pdfURL)
                    title = metadata.title
                    if composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        composer = metadata.author ?? ""
                    }
                } else {
                    title = SongMediaStorage.titleFallback(from: imported.first)
                }
            }

            mediaImportMessage = "Added \(imported.count) file\(imported.count == 1 ? "" : "s")."
        } catch {
            mediaImportMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }
}
