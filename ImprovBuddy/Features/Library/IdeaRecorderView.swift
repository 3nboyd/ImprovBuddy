import AVKit
import SwiftData
import SwiftUI

struct IdeaRecorderView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var services: ServiceContainer
    @Query(sort: \LibraryItem.updatedAt, order: .reverse) private var libraryItems: [LibraryItem]

    @StateObject private var recorder = IdeaRecorderEngine()

    @State private var title = ""
    @State private var notes = ""
    @State private var tagsText = ""
    @State private var statusText = ""
    @State private var recordWithVideo = false
    @State private var previewPlayer: AVPlayer?
    @State private var selectedVideoURL: URL?

    @State private var isScrubbingPlayback = false
    @State private var scrubTime: Double = 0
    @State private var showingPlaybackTools = false
    @State private var sourceKeyName = "C"
    @State private var targetKeyName = "C"

    private let keyChoices = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

    private var hasCapture: Bool {
        recorder.lastRecordedURL != nil || recorder.lastRecordedVideoURL != nil
    }

    private var recorderIdeaItems: [LibraryItem] {
        libraryItems.filter { $0.type == .ideaSnippet }
    }

    private var recentIdeaItems: [LibraryItem] {
        recorderIdeaItems
            .filter { !$0.isRecorderDeleted }
            .sorted { lhs, rhs in
                if lhs.isRecorderPinned != rhs.isRecorderPinned {
                    return lhs.isRecorderPinned && !rhs.isRecorderPinned
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(6)
            .map { $0 }
    }

    private var currentPlaybackTitle: String {
        guard let path = recorder.currentPlaybackURL?.path else { return "Playback" }
        if let item = libraryItems.first(where: { $0.audioFilePath == path }) {
            return item.title
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    if recordWithVideo {
                        recordWithVideo = false
                        return
                    }

                    guard recorder.isVideoCaptureAvailable else {
                        statusText = "Camera is unavailable on this device."
                        return
                    }
                    recordWithVideo = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: recordWithVideo ? "checkmark.square.fill" : "square")
                            .foregroundColor(recordWithVideo ? appEnvironment.accentColor : .secondary)
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

                recentSavesSection
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

                        Text(selectedVideoURL?.lastPathComponent ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay {
                            Text(recordWithVideo ? "Record a video idea to preview it here." : "Tap a saved video item to preview it here.")
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
        .safeAreaInset(edge: .bottom) {
            playbackBar
        }
        .sheet(isPresented: $showingPlaybackTools) {
            playbackToolsSheet
        }
        .onChange(of: recorder.lastRecordedVideoURL) { _, newValue in
            guard let newValue else {
                return
            }
            loadVideoPreview(url: newValue, autoplay: false)
        }
        .onChange(of: recorder.playbackCurrentTime) { _, newValue in
            if !isScrubbingPlayback {
                scrubTime = newValue
            }
        }
        .onChange(of: recorder.currentPlaybackURL?.path) { _, _ in
            isScrubbingPlayback = false
            scrubTime = recorder.playbackCurrentTime
            syncKeySelectionFromCurrentPlayback()
        }
        .onChange(of: recorder.playbackSemitoneShift) { _, _ in
            syncTargetKeyFromSemitone()
        }
        .onDisappear {
            previewPlayer?.pause()
        }
    }

    @ViewBuilder
    private var recentSavesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Saves")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if recentIdeaItems.isEmpty {
                Text("No saved ideas yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(recentIdeaItems) { item in
                            let audioURL = audioURL(for: item)
                            let videoURL = videoURL(for: item)
                            let isCurrent = audioURL.flatMap { recorder.currentPlaybackURL?.path == $0.path } ?? false
                            let isCurrentAndPlaying = isCurrent && recorder.isPlaying
                            let isCurrentVideo = videoURL.flatMap { selectedVideoURL?.path == $0.path } ?? false
                            let isHighlighted = isCurrent || isCurrentVideo

                            Button {
                                handleRowTap(item: item, audioURL: audioURL, videoURL: videoURL)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            if item.isRecorderPinned {
                                                Image(systemName: "pin.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(appEnvironment.accentColor)
                                            }

                                            Text(item.title)
                                                .lineLimit(1)
                                        }
                                        .font(.subheadline.weight(.semibold))

                                        Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 8)

                                    if audioURL != nil {
                                        Image(systemName: isCurrentAndPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(isCurrent ? appEnvironment.accentColor : .secondary)
                                    } else if videoURL != nil {
                                        Image(systemName: "play.rectangle.fill")
                                            .font(.title3)
                                            .foregroundStyle(isCurrentVideo ? appEnvironment.accentColor : .secondary)
                                    } else {
                                        Text("No media")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isHighlighted ? appEnvironment.accentColor.opacity(0.18) : Color.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isHighlighted ? appEnvironment.accentColor.opacity(0.65) : Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    moveToRecentlyDeleted(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    togglePinned(item)
                                } label: {
                                    Label(item.isRecorderPinned ? "Unpin" : "Pin", systemImage: item.isRecorderPinned ? "pin.slash.fill" : "pin.fill")
                                }
                                .tint(appEnvironment.accentColor)
                            }
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
        }
    }

    @ViewBuilder
    private var playbackBar: some View {
        if recorder.currentPlaybackURL != nil {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        recorder.togglePlayPause()
                    } label: {
                        Image(systemName: recorder.isPlaying ? "pause.fill" : "play.fill")
                            .font(.headline.weight(.bold))
                            .frame(width: 38, height: 38)
                            .background(appEnvironment.accentColor.opacity(0.26), in: Circle())
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentPlaybackTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("\(timeString(scrubDisplayTime)) / \(timeString(recorder.playbackDuration))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Button {
                        showingPlaybackTools = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Slider(
                    value: Binding(
                        get: { scrubDisplayTime },
                        set: { scrubTime = $0 }
                    ),
                    in: 0...max(recorder.playbackDuration, 0.1),
                    onEditingChanged: { editing in
                        isScrubbingPlayback = editing
                        if !editing {
                            recorder.seek(to: scrubTime)
                        }
                    }
                )
                .tint(appEnvironment.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider().opacity(0.22)
            }
        }
    }

    private var playbackToolsSheet: some View {
        NavigationStack {
            Form {
                Section("Speed") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Playback Speed")
                            Spacer()
                            Text(String(format: "%.2fx", recorder.playbackRate))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { recorder.playbackRate },
                                set: { recorder.setPlaybackRate($0) }
                            ),
                            in: 0.5...2.0,
                            step: 0.05
                        )
                        .tint(appEnvironment.accentColor)
                    }
                }

                Section("Transpose / Key") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Transpose")
                            Spacer()
                            Text(String(format: "%+.0f st", recorder.playbackSemitoneShift))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { recorder.playbackSemitoneShift },
                                set: { recorder.setPlaybackSemitoneShift($0) }
                            ),
                            in: -12...12,
                            step: 1
                        )
                        .tint(appEnvironment.accentColor)

                        Picker("From Key", selection: $sourceKeyName) {
                            ForEach(keyChoices, id: \.self) { key in
                                Text(key).tag(key)
                            }
                        }
                        .onChange(of: sourceKeyName) { _, _ in
                            applyKeyShiftFromPickers()
                        }

                        Picker("To Key", selection: $targetKeyName) {
                            ForEach(keyChoices, id: \.self) { key in
                                Text(key).tag(key)
                            }
                        }
                        .onChange(of: targetKeyName) { _, _ in
                            applyKeyShiftFromPickers()
                        }
                    }
                }
            }
            .navigationTitle("Playback Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showingPlaybackTools = false
                    }
                }
            }
            .onAppear {
                syncKeySelectionFromCurrentPlayback()
            }
        }
    }

    private var scrubDisplayTime: Double {
        isScrubbingPlayback ? scrubTime : recorder.playbackCurrentTime
    }

    private func handleRowTap(item: LibraryItem, audioURL: URL?, videoURL: URL?) {
        if let audioURL {
            recorder.togglePlayback(for: audioURL)
            syncKeySelectionFrom(item: item)
            return
        }

        if let videoURL {
            loadVideoPreview(url: videoURL, autoplay: true)
            statusText = "Previewing video for \(item.title)."
            return
        }

        statusText = "No playable media found for this item."
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
                ? "Microphone or camera permission denied, or camera unavailable."
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
            keyCenter: sourceKeyName,
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

    private func moveToRecentlyDeleted(_ item: LibraryItem) {
        if let path = item.audioFilePath, recorder.currentPlaybackURL?.path == path {
            recorder.stopPlayback(resetSelection: true)
        }

        if let selectedVideoPath = selectedVideoURL?.path,
           let itemVideoPath = videoURL(for: item)?.path,
           selectedVideoPath == itemVideoPath {
            previewPlayer?.pause()
            previewPlayer = nil
            selectedVideoURL = nil
        }

        item.isRecorderDeleted = true
        item.updatedAt = .now
        try? modelContext.save()
        statusText = "Moved to Recorder Recently Deleted."
    }

    private func togglePinned(_ item: LibraryItem) {
        item.isRecorderPinned.toggle()
        item.updatedAt = .now
        try? modelContext.save()
        statusText = item.isRecorderPinned ? "Pinned to top." : "Unpinned."
    }

    private func audioURL(for item: LibraryItem) -> URL? {
        guard let path = item.audioFilePath, !path.isEmpty else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func videoURL(for item: LibraryItem) -> URL? {
        let prefix = "Video:"
        guard let line = item.notes
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.hasPrefix(prefix) }) else { return nil }

        let rawPath = line
            .replacingOccurrences(of: prefix, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else { return nil }

        let url: URL
        if rawPath.hasPrefix("file://"), let parsed = URL(string: rawPath) {
            url = parsed
        } else {
            url = URL(fileURLWithPath: rawPath)
        }

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func loadVideoPreview(url: URL, autoplay: Bool) {
        selectedVideoURL = url
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        previewPlayer = player
        if autoplay {
            player.seek(to: .zero)
            player.play()
        }
    }

    private func syncKeySelectionFromCurrentPlayback() {
        guard let path = recorder.currentPlaybackURL?.path,
              let item = libraryItems.first(where: { $0.audioFilePath == path }) else {
            sourceKeyName = "C"
            syncTargetKeyFromSemitone()
            return
        }

        syncKeySelectionFrom(item: item)
    }

    private func syncKeySelectionFrom(item: LibraryItem) {
        sourceKeyName = normalizedKeyName(item.keyCenter) ?? "C"
        syncTargetKeyFromSemitone()
    }

    private func applyKeyShiftFromPickers() {
        guard let fromIndex = keyChoices.firstIndex(of: sourceKeyName),
              let toIndex = keyChoices.firstIndex(of: targetKeyName) else {
            return
        }
        recorder.setPlaybackSemitoneShift(Double(toIndex - fromIndex))
    }

    private func syncTargetKeyFromSemitone() {
        guard let sourceIndex = keyChoices.firstIndex(of: sourceKeyName), !keyChoices.isEmpty else { return }
        let shiftedIndex = positiveModulo(sourceIndex + Int(recorder.playbackSemitoneShift), keyChoices.count)
        targetKeyName = keyChoices[shiftedIndex]
    }

    private func normalizedKeyName(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let exact = keyChoices.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact
        }

        let mapped = trimmed
            .replacingOccurrences(of: "Db", with: "C#")
            .replacingOccurrences(of: "D#", with: "Eb")
            .replacingOccurrences(of: "Gb", with: "F#")
            .replacingOccurrences(of: "G#", with: "Ab")
            .replacingOccurrences(of: "A#", with: "Bb")

        return keyChoices.first(where: { $0.caseInsensitiveCompare(mapped) == .orderedSame })
    }

    private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        guard modulus != 0 else { return 0 }
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let minutes = total / 60
        let remaining = total % 60
        return String(format: "%02d:%02d", minutes, remaining)
    }
}
