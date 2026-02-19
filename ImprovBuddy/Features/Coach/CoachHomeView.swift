import SwiftData
import SwiftUI

struct CoachHomeView: View {
    @EnvironmentObject private var services: ServiceContainer
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.title) private var songs: [Song]

    @StateObject private var coordinator = CoachCoordinator()
    @State private var selectedSong: Song?
    @State private var showLiveSession = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
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
                            selectedSong = songs.first
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
                            if let demo = songs.first(where: { $0.title.contains("ii-V-I") }) ?? songs.first {
                                Task {
                                    await coordinator.startSession(
                                        configuration: SessionConfiguration(
                                            song: demo,
                                            inputMode: .midi,
                                            targetTempoBPM: 120,
                                        feel: .swing,
                                        timeSignatureTop: 4,
                                        timeSignatureBottom: 4,
                                        displayKey: "C",
                                        countInBeats: 4,
                                        subdivision: .eighth,
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
            }
        }
    }
}
