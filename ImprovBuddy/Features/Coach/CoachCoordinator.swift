import SwiftData
import SwiftUI

@MainActor
final class CoachCoordinator: ObservableObject {
    @Published var engine: CoachSessionEngine?
    @Published var showingSetup = false
    @Published var showingReport = false
    @Published var latestSession: PracticeSession?
    @Published var latestReport: ProfessorReportSections?
    @Published var errorMessage: String?

    private weak var services: ServiceContainer?

    func configure(services: ServiceContainer) {
        guard self.services == nil else { return }
        self.services = services
        engine = CoachSessionEngine(
            eventBus: services.eventBus,
            theoryResolver: services.theoryResolver,
            metronomeEngine: services.metronomeEngine
        )
    }

    func startSession(configuration: SessionConfiguration) async {
        guard let services, let engine else { return }

        errorMessage = nil

        do {
            switch configuration.inputMode {
            case .midi:
                services.midiManager.start()
            case .mic:
                _ = await services.audioManager.requestMicrophonePermission()
                guard services.audioManager.micPermissionGranted else {
                    errorMessage = "Microphone permission is required for mic mode."
                    return
                }
                try services.audioManager.start(recordAudio: true)
            case .both:
                services.midiManager.start()
                _ = await services.audioManager.requestMicrophonePermission()
                if services.audioManager.micPermissionGranted {
                    try services.audioManager.start(recordAudio: true)
                }
            }

            engine.startSession(configuration: configuration)
        } catch {
            errorMessage = "Failed to start input engine: \(error.localizedDescription)"
        }
    }

    func endSession(modelContext: ModelContext) {
        guard let services, let engine else { return }

        services.audioManager.stop()
        services.metronomeEngine.stop()

        if let session = engine.endSession() {
            latestSession = session
            latestReport = engine.latestReport
            modelContext.insert(session)
            try? modelContext.save()
            showingReport = true
        }
    }

    func pauseResumeTapped() {
        guard let engine else { return }
        engine.isPaused ? engine.resume() : engine.pause()
    }

    func jumpToBar(_ bar: Int) {
        engine?.jumpToBar(bar)
    }

    func restartChorus() {
        engine?.restartChorus()
    }
}
