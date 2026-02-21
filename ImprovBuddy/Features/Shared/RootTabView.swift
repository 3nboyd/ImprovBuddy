import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: ServiceContainer
    @Query(sort: \Song.title) private var songs: [Song]
    @AppStorage("app.didRequestMicPermissionAtLaunch") private var didRequestMicPermissionAtLaunch = false

    var body: some View {
        ZStack {
            TabView {
                SongsWorkspaceView()
                    .tabItem {
                        Label("Songs", systemImage: "music.note.list")
                    }

                RecorderTabView()
                    .tabItem {
                        Label("Recorder", systemImage: "waveform.badge.plus")
                    }

                ToolsHomeView()
                    .tabItem {
                        Label("Tools", systemImage: "metronome")
                    }

                TheoryTabView()
                    .tabItem {
                        Label("Library", systemImage: "books.vertical")
                    }

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
            }

            GlobalToolOverlayHost()
        }
        .task {
            seedDemoSongsIfNeeded()
            await requestMicrophonePermissionIfNeeded()
        }
    }

    private func seedDemoSongsIfNeeded() {
        guard songs.isEmpty else { return }
        Song.demoSongs().forEach(modelContext.insert)
        try? modelContext.save()
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
        let dragTranslation = activeDragKind == kind ? activeDragTranslation : .zero

        overlayContent(for: kind, preferences: binding)
            .position(
                x: anchor.x + CGFloat(prefs.offsetX) + dragTranslation.width,
                y: anchor.y + CGFloat(prefs.offsetY) + dragTranslation.height
            )
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        activeDragKind = kind
                        activeDragTranslation = value.translation
                    }
                    .onEnded { value in
                        let finalPoint = CGPoint(
                            x: anchor.x + CGFloat(prefs.offsetX) + value.translation.width,
                            y: anchor.y + CGFloat(prefs.offsetY) + value.translation.height
                        )
                        commitDrag(kind: kind, finalCenter: finalPoint, in: proxy)
                        activeDragKind = nil
                        activeDragTranslation = .zero
                    }
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
            .frame(width: 38, height: 46)
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
                .frame(width: 28, height: 28)
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
        let safeTopInset = max(proxy.safeAreaInsets.top, 44)
        let safeBottomInset = max(proxy.safeAreaInsets.bottom, 34)
        let width: CGFloat = preferences.isVisible
            ? (preferences.isExpanded ? (kind == .bpm ? 240 : 220) : 38)
            : 32
        let height: CGFloat = preferences.isVisible
            ? (preferences.isExpanded ? 132 : 46)
            : 32

        let leftX = proxy.safeAreaInsets.leading + width * 0.5 + 10
        let rightX = proxy.size.width - proxy.safeAreaInsets.trailing - width * 0.5 - 10
        let topY = safeTopInset + height * 0.5 + 18
        let bottomY = proxy.size.height - safeBottomInset - height * 0.5 - 86

        switch preferences.corner {
        case .topLeft:
            return CGPoint(x: leftX, y: topY)
        case .topRight:
            return CGPoint(x: rightX, y: topY)
        case .bottomLeft:
            return CGPoint(x: leftX, y: bottomY)
        case .bottomRight:
            return CGPoint(x: rightX, y: bottomY)
        }
    }

    private func commitDrag(kind: ToolOverlayKind, finalCenter: CGPoint, in proxy: GeometryProxy) {
        var preferences = preferencesBinding(for: kind).wrappedValue
        preferences.corner = nearestCorner(for: finalCenter, in: proxy)
        let newAnchor = anchorPoint(for: kind, preferences: preferences, in: proxy)
        preferences.offsetX = clamp(Double(finalCenter.x - newAnchor.x), min: -30, max: 30)
        preferences.offsetY = clamp(Double(finalCenter.y - newAnchor.y), min: -24, max: 24)
        preferencesBinding(for: kind).wrappedValue = preferences
    }

    private func nearestCorner(for point: CGPoint, in proxy: GeometryProxy) -> OverlayCorner {
        let horizontalRight = point.x > proxy.size.width * 0.5
        let verticalBottom = point.y > proxy.size.height * 0.5

        switch (horizontalRight, verticalBottom) {
        case (false, false):
            return .topLeft
        case (true, false):
            return .topRight
        case (false, true):
            return .bottomLeft
        case (true, true):
            return .bottomRight
        }
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
        let shouldCapture = prefs.isVisible && prefs.isExpanded

        if shouldCapture {
            if tunerMicLease == nil {
                tunerMicLease = await services.acquireOverlayMicrophoneLease()
            }
        } else if tunerMicLease != nil {
            services.releaseOverlayLease(tunerMicLease)
            tunerMicLease = nil
        }
    }

    private func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}

private struct MiniTunerOverlayView: View {
    @EnvironmentObject private var services: ServiceContainer
    @Binding var preferences: ToolOverlayPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

                Button {
                    preferences.isVisible = false
                    preferences.isExpanded = false
                } label: {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(services.tunerEngine.noteName)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                Text(String(format: "%+.1f", services.tunerEngine.cents))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(centsColor)
            }

            HStack(spacing: 8) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 8)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(centsColor)
                            .frame(width: CGFloat(progress) * 160, height: 8)
                    }
                Text("\(Int(round(services.tunerEngine.confidence * 100)))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(height: 12)

            Text(services.tunerEngine.isStable ? "Stable" : "Listening")
                .font(.caption2)
                .foregroundStyle(services.tunerEngine.isStable ? .green : .secondary)
        }
        .padding(12)
        .frame(width: 220)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var centsColor: Color {
        switch abs(services.tunerEngine.cents) {
        case 0..<6: .green
        case 6..<16: .yellow
        default: .orange
        }
    }

    private var progress: Double {
        max(0, min(1, 1 - (abs(services.tunerEngine.cents) / 35)))
    }
}

private struct MiniBPMOverlayView: View {
    @EnvironmentObject private var services: ServiceContainer
    @Binding var preferences: ToolOverlayPreferences

    @State private var beatFlash = false
    @State private var displayedBPM = 120.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

                Button {
                    preferences.isVisible = false
                    preferences.isExpanded = false
                } label: {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text("\(Int(round(displayedBPM)))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text("BPM")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .opacity(services.metronomeEngine.isRunning ? (beatFlash ? 1 : 0.25) : 0.2)
                    .scaleEffect(beatFlash ? 1.28 : 1)
                    .animation(.easeOut(duration: 0.12), value: beatFlash)
                Spacer()
            }

            HStack(spacing: 8) {
                Button("-") {
                    setBPM(displayedBPM - 1)
                }
                .buttonStyle(.bordered)

                Button(services.metronomeEngine.isRunning ? "Stop" : "Start") {
                    if services.metronomeEngine.isRunning {
                        services.metronomeEngine.stop()
                    } else {
                        services.metronomeEngine.start()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Tap") {
                    if let tappedBPM = services.metronomeEngine.registerTapTempo() {
                        setBPM(tappedBPM)
                    }
                }
                .buttonStyle(.bordered)

                Button("+") {
                    setBPM(displayedBPM + 1)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(width: 240)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .onAppear {
            displayedBPM = services.metronomeEngine.bpm
        }
        .onChange(of: services.metronomeEngine.bpm) { _, newValue in
            displayedBPM = newValue
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

    private func setBPM(_ value: Double) {
        let clamped = max(30, min(320, value))
        displayedBPM = clamped
        services.metronomeEngine.setBPM(clamped)
        services.liveTempoAnalyzer.targetBPM = clamped
        var settings = services.toolsSettings.metronome
        settings.bpm = clamped
        services.toolsSettings.metronome = settings
    }
}
