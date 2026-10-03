import SwiftData
import SwiftUI

struct RootTabView: View {
    private enum RootTab: Hashable {
        case songs
        case recorder
        case tools
        case library
        case settings
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: ServiceContainer
    @Query(sort: \Song.title) private var songs: [Song]
    @AppStorage("app.didRequestMicPermissionAtLaunch") private var didRequestMicPermissionAtLaunch = false
    @State private var selectedTab: RootTab = .songs

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                SongsWorkspaceView()
                    .tag(RootTab.songs)
                    .tabItem {
                        Label("Songs", systemImage: "music.note.list")
                    }

                RecorderTabView()
                    .tag(RootTab.recorder)
                    .tabItem {
                        Label("Recorder", systemImage: "waveform.badge.plus")
                    }

                ToolsHomeView()
                    .tag(RootTab.tools)
                    .tabItem {
                        Label("Tools", systemImage: "metronome")
                    }

                TheoryTabView()
                    .tag(RootTab.library)
                    .tabItem {
                        Label("Library", systemImage: "books.vertical")
                    }

                NavigationStack {
                    SettingsView()
                }
                .tag(RootTab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
            }

            GlobalToolOverlayHost(suppressed: selectedTab == .tools)
        }
        .task {
            seedDemoSongsIfNeeded()
            await requestMicrophonePermissionIfNeeded()
        }
    }

    private func seedDemoSongsIfNeeded() {
        if songs.isEmpty {
            Song.demoSongs().forEach(modelContext.insert)
            try? modelContext.save()
        }
        migrateLegacyDemoSongsIfNeeded()
    }

    private func migrateLegacyDemoSongsIfNeeded() {
        let titleMap: [String: String] = [
            "ii-V-I in C": "Twinkle Twinkle Little Star (example)",
            "F Blues": "Ode to Joy (example)",
            "Rhythm Changes (Simple)": "When the Saints Go Marching In (example)"
        ]

        var didMutate = false
        for song in songs {
            let wasLegacySeed = song.composer == "Demo Pack" || titleMap[song.title] != nil
            guard wasLegacySeed else { continue }
            var songMutated = false

            if let newTitle = titleMap[song.title], song.title != newTitle {
                song.title = newTitle
                songMutated = true
            }
            if song.composer == "Demo Pack" {
                song.composer = nil
                songMutated = true
            }
            if !song.title.lowercased().contains("(example)") {
                song.title = "\(song.title) (example)"
                songMutated = true
            }
            if !song.form.isEmpty {
                song.form = []
                songMutated = true
            }
            if songMutated {
                song.touch()
                didMutate = true
            }
        }

        if didMutate {
            try? modelContext.save()
        }
    }

    @MainActor
    private func requestMicrophonePermissionIfNeeded() async {
        guard !didRequestMicPermissionAtLaunch else { return }
        didRequestMicPermissionAtLaunch = true
        _ = await services.audioManager.requestMicrophonePermission()
    }
}

private struct GlobalToolOverlayHost: View {
    @EnvironmentObject private var services: ServiceContainer
    let suppressed: Bool

    @State private var tunerMicLease: AudioUsageCoordinator.LeaseToken?
    @State private var activeDragKind: ToolOverlayKind?
    @State private var activeDragTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                overlayNode(for: .tuner, in: proxy)
                overlayNode(for: .bpm, in: proxy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .task {
            await syncTunerLeaseIfNeeded()
        }
        .onChange(of: services.toolOverlayPreferences.tuner.isExpanded) { _, _ in
            Task { await syncTunerLeaseIfNeeded() }
        }
        .onChange(of: services.toolOverlayPreferences.tuner.isVisible) { _, _ in
            Task { await syncTunerLeaseIfNeeded() }
        }
        .onChange(of: suppressed) { _, hidden in
            if hidden {
                activeDragKind = nil
                activeDragTranslation = .zero
            }
            Task { await syncTunerLeaseIfNeeded() }
        }
        .onDisappear {
            services.releaseOverlayLease(tunerMicLease)
            tunerMicLease = nil
        }
    }

    @ViewBuilder
    private func overlayNode(for kind: ToolOverlayKind, in proxy: GeometryProxy) -> some View {
        let binding = preferencesBinding(for: kind)
        let prefs = binding.wrappedValue
        let anchor = anchorPoint(for: kind, preferences: prefs, in: proxy)
        let stackedOffset = stackOffset(for: kind)
        let dragTranslation = activeDragKind == kind ? activeDragTranslation : .zero
        let scaleAnchor = unitPoint(for: prefs.corner)

        overlayContent(for: kind, preferences: binding)
            .position(
                x: anchor.x + stackedOffset.width + dragTranslation.width,
                y: anchor.y + dragTranslation.height
            )
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        activeDragKind = kind
                        activeDragTranslation = value.translation
                    }
                    .onEnded { value in
                        let finalPoint = CGPoint(
                            x: anchor.x + stackedOffset.width + value.translation.width,
                            y: anchor.y + value.translation.height
                        )
                        commitDrag(kind: kind, finalCenter: finalPoint, in: proxy)
                        activeDragKind = nil
                        activeDragTranslation = .zero
                    }
            )
            .opacity(suppressed ? 0 : 1)
            .scaleEffect(suppressed ? 0.9 : 1, anchor: scaleAnchor)
            .blur(radius: suppressed ? 0.2 : 0)
            .allowsHitTesting(!suppressed)
            .animation(
                suppressed
                    ? .easeOut(duration: 0.08)
                    : .spring(response: 0.3, dampingFraction: 0.72),
                value: suppressed
            )
            .animation(.easeOut(duration: 0.16), value: prefs.corner)
            .animation(.easeOut(duration: 0.16), value: prefs.isExpanded)
            .animation(.easeOut(duration: 0.16), value: prefs.isVisible)
    }

    @ViewBuilder
    private func overlayContent(
        for kind: ToolOverlayKind,
        preferences: Binding<ToolOverlayPreferences>
    ) -> some View {
        if !preferences.wrappedValue.isVisible {
            restoreHandle(for: kind, preferences: preferences)
        } else if preferences.wrappedValue.isExpanded {
            switch kind {
            case .tuner:
                MiniTunerOverlayView(preferences: preferences)
            case .bpm:
                MiniBPMOverlayView(preferences: preferences)
            }
        } else {
            collapsedHandle(for: kind, preferences: preferences)
        }
    }

    private func collapsedHandle(
        for kind: ToolOverlayKind,
        preferences: Binding<ToolOverlayPreferences>
    ) -> some View {
        Button {
            preferences.wrappedValue.isExpanded = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: kind == .tuner ? "tuningfork" : "metronome")
                    .font(.caption.weight(.bold))
                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.bold))
            }
            .frame(width: 36, height: 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func restoreHandle(
        for kind: ToolOverlayKind,
        preferences: Binding<ToolOverlayPreferences>
    ) -> some View {
        Button {
            preferences.wrappedValue.isVisible = true
        } label: {
            Image(systemName: kind == .tuner ? "tuningfork" : "metronome")
                .font(.caption.weight(.bold))
                .frame(width: 26, height: 26)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func anchorPoint(
        for kind: ToolOverlayKind,
        preferences: ToolOverlayPreferences,
        in proxy: GeometryProxy
    ) -> CGPoint {
        let safeTopInset = max(proxy.safeAreaInsets.top, 48)
        let safeBottomInset = max(proxy.safeAreaInsets.bottom, 34)
        let expandedSize = expandedOverlaySize(for: kind)
        let width: CGFloat = preferences.isVisible
            ? (preferences.isExpanded ? expandedSize.width : 36)
            : 26
        let height: CGFloat = preferences.isVisible
            ? (preferences.isExpanded ? expandedSize.height : 44)
            : 26

        let leftX = proxy.safeAreaInsets.leading + width * 0.5 + 12
        let rightX = proxy.size.width - proxy.safeAreaInsets.trailing - width * 0.5 - 12
        let topY = safeTopInset + height * 0.5 + 24
        let bottomY = proxy.size.height - safeBottomInset - height * 0.5 - 86
        let middleY = (topY + bottomY) * 0.5

        switch preferences.corner {
        case .topLeft:
            return CGPoint(x: leftX, y: topY)
        case .topRight:
            return CGPoint(x: rightX, y: topY)
        case .middleLeft:
            return CGPoint(x: leftX, y: middleY)
        case .middleRight:
            return CGPoint(x: rightX, y: middleY)
        case .bottomLeft:
            return CGPoint(x: leftX, y: bottomY)
        case .bottomRight:
            return CGPoint(x: rightX, y: bottomY)
        }
    }

    private func commitDrag(kind: ToolOverlayKind, finalCenter: CGPoint, in proxy: GeometryProxy) {
        let stackedOffset = stackOffset(for: kind)
        let unstackedCenter = CGPoint(
            x: finalCenter.x - stackedOffset.width,
            y: finalCenter.y
        )
        var preferences = preferencesBinding(for: kind).wrappedValue
        preferences.corner = nearestCorner(
            for: unstackedCenter,
            kind: kind,
            preferences: preferences,
            in: proxy
        )
        preferencesBinding(for: kind).wrappedValue = preferences
    }

    private func nearestCorner(
        for point: CGPoint,
        kind: ToolOverlayKind,
        preferences: ToolOverlayPreferences,
        in proxy: GeometryProxy
    ) -> OverlayCorner {
        let candidates = OverlayCorner.allCases.map { corner -> (OverlayCorner, CGPoint) in
            var candidate = preferences
            candidate.corner = corner
            return (corner, anchorPoint(for: kind, preferences: candidate, in: proxy))
        }

        return candidates.min { lhs, rhs in
            distanceSquared(from: point, to: lhs.1) < distanceSquared(from: point, to: rhs.1)
        }?.0 ?? preferences.corner
    }

    private func expandedOverlaySize(for kind: ToolOverlayKind) -> CGSize {
        switch kind {
        case .tuner:
            return CGSize(width: 146, height: 110)
        case .bpm:
            return CGSize(width: 166, height: 138)
        }
    }

    private func overlaySize(for kind: ToolOverlayKind, preferences: ToolOverlayPreferences) -> CGSize {
        if !preferences.isVisible {
            return CGSize(width: 26, height: 26)
        }
        if preferences.isExpanded {
            return expandedOverlaySize(for: kind)
        }
        return CGSize(width: 36, height: 44)
    }

    private func stackOffset(for kind: ToolOverlayKind) -> CGSize {
        let tunerPrefs = services.toolOverlayPreferences.tuner
        let bpmPrefs = services.toolOverlayPreferences.bpm
        guard tunerPrefs.corner == bpmPrefs.corner else { return .zero }

        let corner = tunerPrefs.corner
        let tunerSize = overlaySize(for: .tuner, preferences: tunerPrefs)
        let bpmSize = overlaySize(for: .bpm, preferences: bpmPrefs)
        let gap: CGFloat = 8
        let xShift = (tunerSize.width * 0.5) + (bpmSize.width * 0.5) + gap

        switch corner {
        case .topLeft, .middleLeft, .bottomLeft:
            return kind == .bpm ? CGSize(width: xShift, height: 0) : .zero
        case .topRight, .middleRight, .bottomRight:
            return kind == .bpm ? CGSize(width: -xShift, height: 0) : .zero
        }
    }

    private func distanceSquared(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx) + (dy * dy)
    }

    private func preferencesBinding(for kind: ToolOverlayKind) -> Binding<ToolOverlayPreferences> {
        Binding(
            get: {
                switch kind {
                case .tuner:
                    return services.toolOverlayPreferences.tuner
                case .bpm:
                    return services.toolOverlayPreferences.bpm
                }
            },
            set: { value in
                switch kind {
                case .tuner:
                    services.toolOverlayPreferences.tuner = value
                case .bpm:
                    services.toolOverlayPreferences.bpm = value
                }
            }
        )
    }

    @MainActor
    private func syncTunerLeaseIfNeeded() async {
        let prefs = services.toolOverlayPreferences.tuner
        let shouldCapture = !suppressed && prefs.isVisible && prefs.isExpanded

        if shouldCapture {
            if tunerMicLease == nil {
                tunerMicLease = await services.acquireOverlayMicrophoneLease()
            }
        } else if tunerMicLease != nil {
            services.releaseOverlayLease(tunerMicLease)
            tunerMicLease = nil
        }
    }

    private func unitPoint(for corner: OverlayCorner) -> UnitPoint {
        switch corner {
        case .topLeft:
            return .topLeading
        case .topRight:
            return .topTrailing
        case .middleLeft:
            return .leading
        case .middleRight:
            return .trailing
        case .bottomLeft:
            return .bottomLeading
        case .bottomRight:
            return .bottomTrailing
        }
    }
}

private struct MiniTunerOverlayView: View {
    @EnvironmentObject private var services: ServiceContainer
    @Binding var preferences: ToolOverlayPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tuner")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    preferences.isExpanded = false
                } label: {
                    Image(systemName: "chevron.compact.up")
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(services.tunerEngine.noteName)
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                Text(String(format: "%+.1f", services.tunerEngine.cents))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(centsColor)
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.red, .yellow, .green, .yellow, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.white.opacity(0.94))
                        .frame(width: 2, height: 14)
                        .offset(x: meterPosition * max(0, geo.size.width - 2))
                }
            }
            .frame(height: 14)

            HStack {
                Text("♭")
                    .foregroundStyle(tuningState == .flat ? .white : .secondary)
                Spacer()
                Text("♮")
                    .foregroundStyle(tuningState == .perfect ? .white : .secondary)
                Spacer()
                Text("♯")
                    .foregroundStyle(tuningState == .sharp ? .white : .secondary)
            }
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .allowsTightening(true)

        }
        .padding(9)
        .frame(width: 146)
        .frame(minHeight: 110)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var centsColor: Color {
        switch abs(services.tunerEngine.cents) {
        case 0..<6: .green
        case 6..<20: .yellow
        default: .orange
        }
    }

    private var meterPosition: CGFloat {
        let normalized = (services.tunerEngine.cents + 50) / 100
        return CGFloat(max(0, min(1, normalized)))
    }

    private enum TuningState {
        case flat
        case perfect
        case sharp
    }

    private var tuningState: TuningState {
        if services.tunerEngine.cents < -6 {
            return .flat
        }
        if services.tunerEngine.cents > 6 {
            return .sharp
        }
        return .perfect
    }
}

private struct MiniBPMOverlayView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var services: ServiceContainer
    @Binding var preferences: ToolOverlayPreferences

    @State private var beatFlash = false
    @State private var displayedBPM = 120.0
    @State private var lastHapticStep = 120
    @State private var nudgeVisualOffset: CGFloat = 0
    @State private var dragBaseBPM: Double?
#if os(iOS)
    private let bpmStepFeedback = UISelectionFeedbackGenerator()
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("BPM")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    preferences.isExpanded = false
                } label: {
                    Image(systemName: "chevron.compact.down")
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text("\(Int(round(displayedBPM)))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text("BPM")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Circle()
                    .fill(appEnvironment.accentColor)
                    .frame(width: 10, height: 10)
                    .opacity(services.metronomeEngine.isRunning ? (beatFlash ? 1 : 0.25) : 0.2)
                    .scaleEffect(beatFlash ? 1.28 : 1)
                    .animation(.easeOut(duration: 0.12), value: beatFlash)
                Spacer()
            }

            HStack(spacing: 10) {
                VStack(spacing: 7) {
                    Button(services.metronomeEngine.isRunning ? "Stop" : "Start") {
                        if services.metronomeEngine.isRunning {
                            services.metronomeEngine.stop()
                        } else {
                            services.metronomeEngine.start()
                        }
                        beatFlash = false
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)

                    Button("Tap") {
                        if let tappedBPM = services.metronomeEngine.registerTapTempo() {
                            setBPM(tappedBPM)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                }
                .frame(maxWidth: .infinity)

                miniTempoVerticalSlider
            }
        }
        .padding(10)
        .frame(width: 166)
        .frame(minHeight: 138)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .onAppear {
            displayedBPM = services.metronomeEngine.bpm
            lastHapticStep = Int(round(displayedBPM))
#if os(iOS)
            bpmStepFeedback.prepare()
#endif
        }
        .onChange(of: services.metronomeEngine.bpm) { _, newValue in
            displayedBPM = newValue
            lastHapticStep = Int(round(newValue))
        }
        .onChange(of: services.metronomeEngine.beatPulseID) { _, _ in
            guard services.metronomeEngine.isRunning else { return }
            withAnimation(.easeOut(duration: 0.1)) {
                beatFlash = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                withAnimation(.easeIn(duration: 0.2)) {
                    beatFlash = false
                }
            }
        }
    }

    private var miniTempoVerticalSlider: some View {
        GeometryReader { geo in
            let height = max(geo.size.height, 1)
            let thumbSize: CGFloat = 18
            let visualTravel = max(1, (height - thumbSize) * 0.5)
            let thumbOffset = max(-visualTravel, min(visualTravel, nudgeVisualOffset))

            ZStack(alignment: .center) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 12, height: height)

                Capsule()
                    .fill(appEnvironment.accentColor.opacity(0.18))
                    .frame(width: 12, height: max(thumbSize, abs(thumbOffset) + thumbSize * 0.35))
                    .offset(y: thumbOffset * 0.5)

                Rectangle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 8, height: 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .stroke(appEnvironment.accentColor.opacity(0.82), lineWidth: 2.2)
                    )
                    .offset(y: thumbOffset)
            }
            .frame(width: 28, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragBaseBPM == nil {
                            dragBaseBPM = displayedBPM
                        }

                        let rawTranslation = value.translation.height
                        nudgeVisualOffset = max(-visualTravel, min(visualTravel, rawTranslation))

                        // Precision nudge: short drags map to small BPM deltas.
                        let clampedBPMTranslation = max(-120.0, min(120.0, Double(rawTranslation)))
                        let delta = -clampedBPMTranslation * 0.08
                        let base = dragBaseBPM ?? displayedBPM
                        setBPM((base + delta).rounded(), emitHaptic: true)
                    }
                    .onEnded { _ in
                        dragBaseBPM = nil
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                            nudgeVisualOffset = 0
                        }
                    }
            )
        }
        .frame(width: 28, height: 90)
    }

    private func setBPM(_ value: Double, emitHaptic: Bool = false) {
        let clamped = max(30, min(320, value))
        displayedBPM = clamped
        services.metronomeEngine.setBPM(clamped)
        services.liveTempoAnalyzer.targetBPM = clamped
        var settings = services.toolsSettings.metronome
        settings.bpm = clamped
        services.toolsSettings.metronome = settings
        emitBPMStepHapticIfNeeded(for: clamped, enabled: emitHaptic)
    }

    private func emitBPMStepHapticIfNeeded(for value: Double, enabled: Bool) {
        guard enabled else { return }
        let newStep = Int(round(value))
        guard newStep != lastHapticStep else { return }
        lastHapticStep = newStep
#if os(iOS)
        bpmStepFeedback.selectionChanged()
        bpmStepFeedback.prepare()
#endif
    }
}
