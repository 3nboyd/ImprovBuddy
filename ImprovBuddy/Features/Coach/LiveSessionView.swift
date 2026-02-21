import SwiftUI
#if os(iOS)
import UIKit
#endif

struct LiveSessionView: View {
    @ObservedObject var engine: CoachSessionEngine

    let onPauseResume: () -> Void
    let onEnd: () -> Void
    let onJumpToBar: (Int) -> Void
    let onRestartChorus: () -> Void

    @State private var jumpBarText = "1"
    @State private var showMetronomePopup = false
    @State private var isKeyScrubActive = false
    @State private var keyScrubAnchorIndex = 0

    private var keys: [String] {
        TheoryKey.all.map(\.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    metricsGrid
                    chordSheet
                    controlsBlock
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 22)
            }
            .safeAreaInset(edge: .top) {
                topSessionBar
            }
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) {
                    onEnd()
                } label: {
                    Text("End Session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.top, 8)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Live Coach")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showMetronomePopup) {
                metronomePopup
                    .presentationDetents([.medium])
            }
        }
    }

    private var topSessionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Song Key")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Label(
                    isKeyScrubActive
                    ? "Sliding… \(TheoryDisplayFormatter.displaySymbol(engine.displayKeyName))"
                    : "Key \(TheoryDisplayFormatter.displaySymbol(engine.displayKeyName))",
                    systemImage: isKeyScrubActive ? "hand.draw.fill" : "music.note"
                )
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(isKeyScrubActive ? 0.28 : 0.16), in: Capsule())
                .foregroundStyle(Color.accentColor)
                .gesture(keyScrubGesture)
            }

            Spacer()

            Button {
                showMetronomePopup = true
            } label: {
                Label("Met", systemImage: "metronome")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Metronome Options")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
            MetricTile(
                title: "Tempo",
                value: String(format: "%.0f", engine.targetTempoBPM),
                subtitle: String(format: "live %.1f BPM", engine.liveEstimatedBPM)
            )
            MetricTile(
                title: "Timing",
                value: String(format: "%.0f ms", engine.latestTimingErrorMs),
                subtitle: engine.tempoDriftState == .stable ? "stable" : "drifting"
            )
            MetricTile(
                title: "Form",
                value: "Bar \(engine.currentMeasureIndex + 1)",
                subtitle: "Chorus \(engine.currentChorusIndex + 1)/\(engine.targetChorusCount)"
            )
            MetricTile(
                title: "Harmony",
                value: engine.harmonyState.displayName,
                subtitle: TheoryDisplayFormatter.displaySymbol(engine.currentChordSymbol)
            )
        }
    }

    private var chordSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chord Sheet")
                .font(.headline)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(engine.formMeasures.enumerated()), id: \.element.id) { index, measure in
                            chordMeasureCell(measure: measure, index: index)
                                .id(index)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    proxy.scrollTo(engine.currentMeasureIndex, anchor: .center)
                }
                .onChange(of: engine.currentMeasureIndex) { _, measureIndex in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(measureIndex, anchor: .center)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func chordMeasureCell(measure: Measure, index: Int) -> some View {
        let isActive = index == engine.currentMeasureIndex

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(index + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                if let section = measure.sectionLabel, !section.isEmpty {
                    Text(section)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(engine.displayedChordSymbol(for: measure))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 92, height: 76, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.accentColor.opacity(0.24) : Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.accentColor : Color.white.opacity(0.1), lineWidth: isActive ? 1.5 : 1)
        )
    }

    private var controlsBlock: some View {
        VStack(spacing: 12) {
            Text(engine.coachPrompt)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button(engine.isPaused ? "Resume" : "Pause") {
                        onPauseResume()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Restart Chorus") {
                        onRestartChorus()
                    }
                    .buttonStyle(.bordered)
                }

                VStack(spacing: 8) {
                    Button(engine.isPaused ? "Resume" : "Pause") {
                        onPauseResume()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Restart Chorus") {
                        onRestartChorus()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Stepper(
                "Choruses: \(engine.targetChorusCount)",
                value: Binding(
                    get: { engine.targetChorusCount },
                    set: { engine.setTargetChorusCount($0) }
                ),
                in: 1...32
            )

            HStack(spacing: 12) {
                TextField("Bar", text: $jumpBarText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)

                Button("Jump to Bar") {
                    let bar = Int(jumpBarText) ?? 1
                    onJumpToBar(max(1, bar))
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var keyScrubGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.18)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    beginKeyScrubIfNeeded()
                case let .second(true, drag?):
                    beginKeyScrubIfNeeded()
                    updateKeyScrub(with: drag.translation.height)
                default:
                    break
                }
            }
            .onEnded { _ in
                isKeyScrubActive = false
            }
    }

    private func beginKeyScrubIfNeeded() {
        guard !isKeyScrubActive else { return }
        keyScrubAnchorIndex = keys.firstIndex(of: engine.displayKeyName) ?? 0
        isKeyScrubActive = true
    }

    private func updateKeyScrub(with verticalTranslation: CGFloat) {
        guard isKeyScrubActive, !keys.isEmpty else { return }
        let stepsMoved = Int((-verticalTranslation / 24).rounded(.toNearestOrAwayFromZero))
        let targetIndex = max(0, min(keys.count - 1, keyScrubAnchorIndex + stepsMoved))
        let targetKey = keys[targetIndex]
        guard targetKey != engine.displayKeyName else { return }
        engine.updateDisplayKeyName(targetKey)
        emitSelectionHaptic()
    }

    private func emitSelectionHaptic() {
#if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
#endif
    }

    private var metronomePopup: some View {
        NavigationStack {
            Form {
                Toggle("Constant Metronome", isOn: Binding(
                    get: { engine.isConstantMetEnabled },
                    set: { engine.setConstantMetronomeEnabled($0) }
                ))

                Picker("Sound", selection: Binding(
                    get: { engine.metronomeSoundSet },
                    set: { engine.setMetronomeSoundSet($0) }
                )) {
                    ForEach(MetronomeSoundSet.allCases) { sound in
                        Text(sound.displayName).tag(sound)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Volume")
                    Slider(
                        value: Binding(
                            get: { engine.metronomeVolume },
                            set: { engine.setMetronomeVolume($0) }
                        ),
                        in: 0...1
                    )
                }

                if engine.isRunning {
                    Text(engine.isConstantMetEnabled ? "Click stays on during the session." : "Count-in remains audible; turn on Constant Metronome to keep click running.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Metronome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
