import SwiftData
import SwiftUI

struct IdeaRecorderView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var services: ServiceContainer
    @Query(sort: \LibraryItem.updatedAt, order: .reverse) private var libraryItems: [LibraryItem]

    @StateObject private var recorder = IdeaRecorderEngine()

    @State private var title = "Idea"
    @State private var statusText = ""

    @State private var isScrubbingPlayback = false
    @State private var scrubTime: Double = 0
    @State private var renamingItem: LibraryItem?
    @State private var renameDraft = ""

    private var hasCapture: Bool {
        recorder.lastRecordedURL != nil
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
            TextField("Base title (used for takes)", text: $title)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)

            if !statusText.isEmpty {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            recentSavesSection
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Idea Recorder")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                playbackBar
                recorderControlDock
            }
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider().opacity(0.22)
            }
        }
        .alert("Rename Recording", isPresented: Binding(
            get: { renamingItem != nil },
            set: { isPresented in
                if !isPresented { renamingItem = nil }
            }
        )) {
            TextField("Title", text: $renameDraft)
            Button("Cancel", role: .cancel) {
                renamingItem = nil
            }
            Button("Save") {
                applyRename()
            }
        }
        .onChange(of: recorder.playbackCurrentTime) { _, newValue in
            if !isScrubbingPlayback {
                scrubTime = newValue
            }
        }
        .onChange(of: recorder.currentPlaybackURL?.path) { _, _ in
            isScrubbingPlayback = false
            scrubTime = recorder.playbackCurrentTime
        }
        .onChange(of: recorder.playbackErrorMessage) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            statusText = "Playback failed: \(newValue)"
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
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            } else {
                List {
                    ForEach(recentIdeaItems) { item in
                        ideaRow(item)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func ideaRow(_ item: LibraryItem) -> some View {
        let audioURL = audioURL(for: item)
        let isCurrent = audioURL.flatMap { recorder.currentPlaybackURL?.path == $0.path } ?? false
        let isCurrentAndPlaying = isCurrent && recorder.isPlaying
        let isHighlighted = isCurrent

        return HStack(spacing: 8) {
            Button {
                handleRowTap(item: item, audioURL: audioURL)
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
                    } else {
                        Text("Missing audio")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                beginRename(item)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
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

    @ViewBuilder
    private var playbackBar: some View {
        if recorder.currentPlaybackURL != nil {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        if !recorder.togglePlayPause(), let message = recorder.playbackErrorMessage {
                            statusText = "Playback failed: \(message)"
                        }
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
                .animation(.linear(duration: 0.08), value: scrubDisplayTime)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
    }

    private var recorderControlDock: some View {
        HStack(alignment: .bottom, spacing: 12) {
            transposeControl

            VStack(spacing: 8) {
                if recorder.isRecording {
                    Text(recordingTimeString(recorder.recordingElapsed))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Button {
                    Task {
                        await toggleRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 92, height: 92)
                        Circle()
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            .frame(width: 92, height: 92)

                        if recorder.isRecording {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.red)
                                .frame(width: 34, height: 34)
                        } else {
                            Circle()
                                .fill(.red)
                                .frame(width: 58, height: 58)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)

            speedControl
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var transposeControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Transpose")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(String(format: "%+.0f st", recorder.playbackSemitoneShift))
                    .font(.caption.monospacedDigit())
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

            HStack(spacing: 8) {
                compactAdjustButton(systemName: "minus") {
                    recorder.setPlaybackSemitoneShift(recorder.playbackSemitoneShift - 1)
                }
                compactAdjustButton(systemName: "plus") {
                    recorder.setPlaybackSemitoneShift(recorder.playbackSemitoneShift + 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speedControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Speed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(String(format: "%.2fx", recorder.playbackRate))
                    .font(.caption.monospacedDigit())
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

            HStack(spacing: 8) {
                compactAdjustButton(systemName: "minus") {
                    recorder.setPlaybackRate(recorder.playbackRate - 0.05)
                }
                compactAdjustButton(systemName: "plus") {
                    recorder.setPlaybackRate(recorder.playbackRate + 0.05)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactAdjustButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var scrubDisplayTime: Double {
        isScrubbingPlayback ? scrubTime : recorder.playbackCurrentTime
    }

    private func handleRowTap(item: LibraryItem, audioURL: URL?) {
        guard let audioURL else {
            statusText = "No playable audio found for this item."
            return
        }

        if recorder.togglePlayback(for: audioURL) {
            statusText = recorder.isPlaying ? "Playing \(item.title)." : "Paused \(item.title)."
        } else if let message = recorder.playbackErrorMessage {
            statusText = "Playback failed: \(message)"
        }
    }

    private func toggleRecording() async {
        if recorder.isRecording {
            recorder.stopRecording()
            saveLatestSnippet()
            return
        }

        let granted = await recorder.requestPermission()
        guard granted else {
            statusText = "Microphone permission denied."
            return
        }

        do {
            recorder.captureMetronomeReference(from: services.metronomeEngine)
            try recorder.startRecording()
            statusText = "Recording audio..."
        } catch {
            statusText = "Recording failed: \(error.localizedDescription)"
        }
    }

    private func saveLatestSnippet() {
        guard hasCapture else { return }
        let baseTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Idea"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        let item = LibraryItem(
            type: .ideaSnippet,
            title: nextIndexedTitle(for: baseTitle),
            notes: "",
            tags: [],
            audioFilePath: recorder.lastRecordedURL?.path,
            keyCenter: "C",
            tempoBPM: nil,
            recorderMetronomeReference: recorder.lastMetronomeReference
        )

        modelContext.insert(item)
        try? modelContext.save()

        statusText = "Saved \(item.title)."
    }

    private func beginRename(_ item: LibraryItem) {
        renamingItem = item
        renameDraft = item.title
    }

    private func applyRename() {
        guard let renamingItem else { return }
        let cleaned = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            self.renamingItem = nil
            return
        }
        renamingItem.title = cleaned
        renamingItem.updatedAt = .now
        try? modelContext.save()
        statusText = "Renamed to \(cleaned)."
        self.renamingItem = nil
    }

    private func nextIndexedTitle(for base: String) -> String {
        let escapedBase = NSRegularExpression.escapedPattern(for: base)
        let pattern = "^\(escapedBase) \\((\\d+)\\)$"
        let regex = try? NSRegularExpression(pattern: pattern)

        var maxIndex = 0
        for item in recorderIdeaItems {
            if item.title == base {
                maxIndex = max(maxIndex, 1)
                continue
            }
            guard let regex else { continue }
            let nsTitle = item.title as NSString
            let range = NSRange(location: 0, length: nsTitle.length)
            guard let match = regex.firstMatch(in: item.title, options: [], range: range),
                  match.numberOfRanges > 1 else { continue }
            let numberRange = match.range(at: 1)
            guard numberRange.location != NSNotFound else { continue }
            let raw = nsTitle.substring(with: numberRange)
            if let index = Int(raw) {
                maxIndex = max(maxIndex, index)
            }
        }

        return "\(base) (\(maxIndex + 1))"
    }

    private func moveToRecentlyDeleted(_ item: LibraryItem) {
        if let path = item.audioFilePath, recorder.currentPlaybackURL?.path == path {
            recorder.stopPlayback(resetSelection: true)
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

    private func timeString(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let minutes = total / 60
        let remaining = total % 60
        return String(format: "%02d:%02d", minutes, remaining)
    }

    private func recordingTimeString(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let minutes = total / 60
        let remaining = total % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}
