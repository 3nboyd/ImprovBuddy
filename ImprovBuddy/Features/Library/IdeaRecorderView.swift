import AVKit
import SwiftData
import SwiftUI

struct IdeaRecorderView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: ServiceContainer

    @StateObject private var recorder = IdeaRecorderEngine()

    @State private var title = ""
    @State private var notes = ""
    @State private var tagsText = ""
    @State private var statusText = ""
    @State private var recordWithVideo = false
    @State private var previewPlayer: AVPlayer?

    private var hasCapture: Bool {
        recorder.lastRecordedURL != nil || recorder.lastRecordedVideoURL != nil
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    recordWithVideo.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: recordWithVideo ? "checkmark.square.fill" : "square")
                            .foregroundColor(recordWithVideo ? .accentColor : .secondary)
                        Text("Record with Video")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button(recorder.isRecording ? "Stop" : "Record") {
                        Task {
                            await toggleRecording()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button(recorder.isPlaying ? "Stop Audio" : "Play Last Audio") {
                        if recorder.isPlaying {
                            recorder.stopPlayback()
                        } else {
                            recorder.playLatest()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(recorder.lastRecordedURL == nil)

                    Button("Save") {
                        saveLatestSnippet()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasCapture)
                }

                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...3)
                    .textFieldStyle(.roundedBorder)

                TextField("Tags (comma)", text: $tagsText)
                    .textFieldStyle(.roundedBorder)

                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Video Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let player = previewPlayer {
                    VideoPlayer(player: player)
                        .frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    HStack(spacing: 10) {
                        Button("Replay") {
                            player.seek(to: .zero)
                            player.play()
                        }
                        .buttonStyle(.bordered)

                        Text(recorder.lastRecordedVideoURL?.lastPathComponent ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay {
                            Text(recordWithVideo ? "Record a video idea to preview it here." : "Enable Record with Video to preview here.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                        .frame(height: 170)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Idea Recorder")
        .onChange(of: recorder.lastRecordedVideoURL) { _, newValue in
            guard let newValue else {
                previewPlayer = nil
                return
            }
            let player = AVPlayer(url: newValue)
            player.actionAtItemEnd = .pause
            previewPlayer = player
        }
        .onDisappear {
            previewPlayer?.pause()
        }
    }

    private func toggleRecording() async {
        if recorder.isRecording {
            recorder.stopRecording()
            statusText = recordWithVideo ? "Video stopped. Preview is ready below." : "Recording stopped."
            return
        }

        let granted = await recorder.requestPermission(includeVideo: recordWithVideo)
        guard granted else {
            statusText = recordWithVideo
                ? "Microphone or camera permission denied."
                : "Microphone permission denied."
            return
        }

        do {
            recorder.captureMetronomeReference(from: services.metronomeEngine)
            try recorder.startRecording(withVideo: recordWithVideo)
            statusText = recordWithVideo ? "Recording video..." : "Recording audio..."
        } catch {
            statusText = "Recording failed: \(error.localizedDescription)"
        }
    }

    private func saveLatestSnippet() {
        guard hasCapture else { return }

        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var storedNotes = notes
        if let videoPath = recorder.lastRecordedVideoURL?.path {
            let marker = "Video: \(videoPath)"
            storedNotes = storedNotes.isEmpty ? marker : "\(storedNotes)\n\(marker)"
        }

        let item = LibraryItem(
            type: .ideaSnippet,
            title: title.isEmpty ? "Idea \(Date().formatted(date: .numeric, time: .shortened))" : title,
            notes: storedNotes,
            tags: tags,
            audioFilePath: recorder.lastRecordedURL?.path,
            keyCenter: nil,
            tempoBPM: nil,
            recorderMetronomeReference: recorder.lastMetronomeReference
        )

        modelContext.insert(item)
        try? modelContext.save()

        title = ""
        notes = ""
        tagsText = ""
        statusText = recorder.lastRecordedVideoURL != nil
            ? "Saved. Video preview kept below."
            : "Saved to Library."
    }
}
