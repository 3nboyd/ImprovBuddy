import SwiftData
import SwiftUI

struct IdeaRecorderView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LibraryItem.createdAt, order: .reverse) private var allItems: [LibraryItem]

    @StateObject private var recorder = IdeaRecorderEngine()

    @State private var title = ""
    @State private var notes = ""
    @State private var tagsText = ""
    @State private var keyCenter = ""
    @State private var tempoText = ""
    @State private var statusText = ""

    private var snippets: [LibraryItem] {
        allItems.filter { $0.type == .ideaSnippet }
    }

    var body: some View {
        VStack(spacing: 14) {
            Form {
                Section("Record") {
                    HStack(spacing: 12) {
                        Button(recorder.isRecording ? "Stop" : "Record") {
                            Task {
                                await toggleRecording()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button(recorder.isPlaying ? "Stop Playback" : "Play Last") {
                            if recorder.isPlaying {
                                recorder.stopPlayback()
                            } else {
                                recorder.playLatest()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(recorder.lastRecordedURL == nil)
                    }

                    if !statusText.isEmpty {
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Tag Latest") {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                    TextField("Tags (comma)", text: $tagsText)
                    HStack {
                        TextField("Key", text: $keyCenter)
                        TextField("Tempo", text: $tempoText)
                            .keyboardType(.numberPad)
                    }

                    Button("Save to Library") {
                        saveLatestSnippet()
                    }
                    .disabled(recorder.lastRecordedURL == nil)
                }
            }

            if snippets.isEmpty {
                ContentUnavailableView("No snippets yet", systemImage: "waveform.badge.plus")
            } else {
                List(snippets) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                        if !item.notes.isEmpty {
                            Text(item.notes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let key = item.keyCenter, let tempo = item.tempoBPM {
                            Text("\(key) • \(Int(tempo)) BPM")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Play") {
                                if let path = item.audioFilePath {
                                    recorder.play(url: URL(fileURLWithPath: path))
                                }
                            }
                            .buttonStyle(.bordered)

                            if !item.tags.isEmpty {
                                Text(item.tags.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }
        }
        .navigationTitle("Idea Recorder")
    }

    private func toggleRecording() async {
        if recorder.isRecording {
            recorder.stopRecording()
            statusText = "Recording stopped. Add tags and save."
            return
        }

        let granted = await recorder.requestPermission()
        guard granted else {
            statusText = "Microphone permission denied."
            return
        }

        do {
            try recorder.startRecording()
            statusText = "Recording..."
        } catch {
            statusText = "Recording failed: \(error.localizedDescription)"
        }
    }

    private func saveLatestSnippet() {
        guard let url = recorder.lastRecordedURL else { return }

        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let tempo = Double(tempoText)
        let item = LibraryItem(
            type: .ideaSnippet,
            title: title.isEmpty ? "Idea \(Date().formatted(date: .numeric, time: .shortened))" : title,
            notes: notes,
            tags: tags,
            audioFilePath: url.path,
            keyCenter: keyCenter.isEmpty ? nil : keyCenter,
            tempoBPM: tempo
        )

        modelContext.insert(item)
        try? modelContext.save()

        title = ""
        notes = ""
        tagsText = ""
        keyCenter = ""
        tempoText = ""
        statusText = "Saved to Library."
    }
}
