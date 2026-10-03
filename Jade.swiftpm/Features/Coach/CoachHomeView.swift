import SwiftData
import SwiftUI

private enum CoachHomePane: String, CaseIterable, Identifiable {
    case coach
    case songs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coach: "Coach"
        case .songs: "Songs"
        }
    }
}

struct CoachHomeView: View {
    @EnvironmentObject private var services: ServiceContainer
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.title) private var songs: [Song]

    @StateObject private var coordinator = CoachCoordinator()
    @State private var activePane: CoachHomePane = .coach
    @State private var selectedSong: Song?
    @State private var showLiveSession = false
    @State private var showingCreateSongSheet = false
    @State private var editingSong: Song?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Coach Pane", selection: $activePane) {
                    ForEach(CoachHomePane.allCases) { pane in
                        Text(pane.title).tag(pane)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)

                Divider()

                Group {
                    switch activePane {
                    case .coach:
                        coachPane
                    case .songs:
                        songsPane
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Coach")
            .sheet(isPresented: $coordinator.showingSetup) {
                SessionSetupView(songs: songs, initialSong: selectedSong) { configuration in
                    Task {
                        await coordinator.startSession(configuration: configuration)
                        if coordinator.errorMessage == nil {
                            showLiveSession = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCreateSongSheet) {
                SongEditorView(song: nil)
            }
            .sheet(item: $editingSong) { song in
                SongEditorView(song: song)
            }
            .fullScreenCover(isPresented: $showLiveSession, onDismiss: {
                coordinator.engine?.resetForNextSession()
            }) {
                if let engine = coordinator.engine {
                    LiveSessionView(
                        engine: engine,
                        onPauseResume: { coordinator.pauseResumeTapped() },
                        onEnd: {
                            coordinator.endSession(modelContext: modelContext)
                            showLiveSession = false
                        },
                        onJumpToBar: { coordinator.jumpToBar($0) },
                        onRestartChorus: { coordinator.restartChorus() }
                    )
                }
            }
            .sheet(isPresented: $coordinator.showingReport) {
                if let session = coordinator.latestSession,
                   let report = coordinator.latestReport {
                    SessionReportView(session: session, report: report)
                }
            }
            .onAppear {
                coordinator.configure(services: services)
                services.midiManager.refreshSources()
                if selectedSong == nil {
                    selectedSong = songs.first
                }
            }
            .onChange(of: songs) { _, newSongs in
                guard let selectedSong else {
                    self.selectedSong = newSongs.first
                    return
                }
                if !newSongs.contains(where: { $0.id == selectedSong.id }) {
                    self.selectedSong = newSongs.first
                }
            }
        }
    }

    private var coachPane: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let selectedSong {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current Song")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(selectedSong.title)
                                    .font(.headline)
                            }

                            Spacer()

                            Button("Change") {
                                activePane = .songs
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack(spacing: 12) {
                            Text("\(Int(selectedSong.defaultTempoBPM)) BPM")
                            Text(selectedSong.feel.displayName)
                            Text("\(selectedSong.timeSignatureTop)/\(selectedSong.timeSignatureBottom)")
                            if let composer = selectedSong.composer, !composer.isEmpty {
                                Text(composer)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                if services.midiManager.sources.isEmpty {
                    ContentUnavailableView(
                        "Connect MIDI Keyboard (Recommended)",
                        systemImage: "pianokeys",
                        description: Text("For the fastest demo flow, connect a MIDI keyboard. Mic mode is still supported.")
                    )
                    .frame(maxHeight: 260)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connected MIDI Sources")
                            .font(.headline)
                        ForEach(services.midiManager.sources) { source in
                            HStack {
                                Text(source.name)
                                Spacer()
                                if services.midiManager.connectedSourceIDs.contains(source.id) {
                                    Label("Connected", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(spacing: 12) {
                    Button {
                        if selectedSong == nil {
                            selectedSong = songs.first
                        }
                        coordinator.showingSetup = true
                    } label: {
                        Text("Start Session")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(songs.isEmpty)

                    Button {
                        if let demo = selectedSong ?? songs.first(where: { $0.title.contains("ii-V-I") }) ?? songs.first {
                            Task {
                                await coordinator.startSession(
                                    configuration: SessionConfiguration(
                                        song: demo,
                                        inputMode: .midi,
                                        targetTempoBPM: max(40, demo.defaultTempoBPM),
                                        feel: demo.feel,
                                        timeSignatureTop: demo.timeSignatureTop,
                                        timeSignatureBottom: demo.timeSignatureBottom,
                                        displayKey: "C",
                                        countInBeats: 4,
                                        subdivision: demo.feel == .swing ? .triplet : .eighth,
                                        theoryContext: .default
                                    )
                                )
                                if coordinator.errorMessage == nil {
                                    showLiveSession = true
                                }
                            }
                        }
                    } label: {
                        Text("Run Demo Session")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(songs.isEmpty)
                }

                if let error = coordinator.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }

    private var songsPane: some View {
        List {
            Section {
                Button {
                    showingCreateSongSheet = true
                } label: {
                    Label("New Song", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
            }

            Section("Song Library") {
                ForEach(songs) { song in
                    HStack(spacing: 12) {
                        Button {
                            selectedSong = song
                            activePane = .coach
                        } label: {
                            CoachSongRow(song: song, isSelected: selectedSong?.id == song.id)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Button {
                            editingSong = song
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteSongs)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func deleteSongs(at offsets: IndexSet) {
        offsets.forEach { index in
            modelContext.delete(songs[index])
        }
        try? modelContext.save()
    }
}

private struct CoachSongRow: View {
    let song: Song
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(song.title)
                    .font(.headline)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.subheadline)
                }
            }

            HStack(spacing: 10) {
                Text("\(Int(song.defaultTempoBPM)) BPM")
                Text(song.feel.displayName)
                Text("\(song.timeSignatureTop)/\(song.timeSignatureBottom)")
                if let composer = song.composer, !composer.isEmpty {
                    Text(composer)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
