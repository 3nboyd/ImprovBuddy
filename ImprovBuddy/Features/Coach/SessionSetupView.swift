import SwiftUI

struct SessionSetupView: View {
    @Environment(\.dismiss) private var dismiss

    let songs: [Song]
    let initialSong: Song?
    let onStart: (SessionConfiguration) -> Void

    @State private var selectedSongID: UUID?
    @State private var inputMode: InputMode = .midi
    @State private var tempoBPM: Double = 120
    @State private var feel: FeelType = .swing
    @State private var timeSigTop = 4
    @State private var timeSigBottom = 4
    @State private var displayKey = TheoryKey.defaultKey.name
    @State private var theoryInstrument: TheoryInstrumentTransposition = .concert
    @State private var theoryTier: TheoryTier = .core
    @State private var countIn = 4

    var selectedSong: Song? {
        songs.first(where: { $0.id == selectedSongID })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Song") {
                    Picker("Choose Song", selection: Binding(get: {
                        selectedSongID ?? songs.first?.id
                    }, set: { selectedSongID = $0 })) {
                        ForEach(songs) { song in
                            Text(song.title).tag(Optional(song.id))
                        }
                    }
                }

                Section("Input") {
                    Picker("Input Mode", selection: $inputMode) {
                        ForEach(InputMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Session") {
                    HStack {
                        Slider(value: $tempoBPM, in: 40...320, step: 1)
                        Text("\(Int(tempoBPM))")
                            .frame(width: 40)
                            .monospacedDigit()
                    }

                    Picker("Feel", selection: $feel) {
                        ForEach(FeelType.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Stepper("Time Signature Top: \(timeSigTop)", value: $timeSigTop, in: 2...12)
                    Stepper("Time Signature Bottom: \(timeSigBottom)", value: $timeSigBottom, in: 2...8)
                    Picker("Key", selection: $displayKey) {
                        ForEach(TheoryKey.all, id: \.name) { key in
                            Text(key.name).tag(key.name)
                        }
                    }
                    Picker("Instrument", selection: $theoryInstrument) {
                        ForEach(TheoryInstrumentTransposition.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Theory Tier", selection: $theoryTier) {
                        ForEach(TheoryTier.allCases) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper("Count-in beats: \(countIn)", value: $countIn, in: 0...8)
                }
            }
            .navigationTitle("Start Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        guard let song = selectedSong else { return }
                        onStart(
                            SessionConfiguration(
                                song: song,
                                inputMode: inputMode,
                                targetTempoBPM: tempoBPM,
                                feel: feel,
                                timeSignatureTop: timeSigTop,
                                timeSignatureBottom: timeSigBottom,
                                displayKey: displayKey,
                                countInBeats: countIn,
                                subdivision: feel == .swing ? .triplet : .eighth,
                                theoryContext: TheoryContext(
                                    concertKeyName: displayKey,
                                    instrument: theoryInstrument,
                                    clef: .treble,
                                    preferredTier: theoryTier,
                                    scoringUsesScaleAwareness: true
                                )
                            )
                        )
                        dismiss()
                    }
                    .disabled(selectedSong == nil)
                }
            }
            .onAppear {
                if selectedSongID == nil {
                    selectedSongID = initialSong?.id ?? songs.first?.id
                    if let song = initialSong ?? songs.first {
                        tempoBPM = song.defaultTempoBPM
                        feel = song.feel
                        timeSigTop = song.timeSignatureTop
                        timeSigBottom = song.timeSignatureBottom
                    }
                }
            }
        }
    }
}
