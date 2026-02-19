import AVFoundation
import Foundation

enum AudioEngineError: LocalizedError {
    case microphonePermissionDenied
    case noInputRouteAvailable

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission is required."
        case .noInputRouteAvailable:
            return "No microphone input route is currently available."
        }
    }
}

final class AudioEngineManager: ObservableObject {
    @Published private(set) var micPermissionGranted = false
    @Published private(set) var isRunning = false
    @Published private(set) var currentRouteName = ""
    @Published private(set) var lastErrorMessage: String?

    private let eventBus: UnifiedEventBus
    private let analysisQueue = DispatchQueue(label: "com.nbz.improvbuddy.analysis", qos: .userInitiated)
    private let ringBuffer = FloatRingBuffer(capacity: 96_000)

    private let engine = AVAudioEngine()
    private var onsetDetector = OnsetDetector()
    private var pitchDetector: PitchDetector?

    private var recordingFile: AVAudioFile?
    private var shouldRecordAudio = false

    init(eventBus: UnifiedEventBus) {
        self.eventBus = eventBus
        observeRouteChanges()
        updateRouteName()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @MainActor
    func requestMicrophonePermission() async -> Bool {
        let granted = await Self.requestMicrophonePermissionFromSystem()
        publishOnMain { [weak self] in
            self?.micPermissionGranted = granted
        }
        return granted
    }

    @MainActor
    func start(recordAudio: Bool = false) throws {
        if isRunning {
            shouldRecordAudio = shouldRecordAudio || recordAudio
            return
        }

        if !micPermissionGranted && AVAudioSession.sharedInstance().recordPermission != .granted {
            publishOnMain { [weak self] in
                self?.lastErrorMessage = AudioEngineError.microphonePermissionDenied.localizedDescription
            }
            throw AudioEngineError.microphonePermissionDenied
        }

        shouldRecordAudio = recordAudio
        publishOnMain { [weak self] in
            self?.lastErrorMessage = nil
        }

        try configureAudioSession()
        try setupTap()

        if shouldRecordAudio {
            recordingFile = try makeRecordingFile()
        }

        engine.prepare()
        try engine.start()
        publishOnMain { [weak self] in
            self?.isRunning = true
        }
        updateRouteName()
    }

    @MainActor
    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        recordingFile = nil
        publishOnMain { [weak self] in
            self?.isRunning = false
        }
        ringBuffer.clear()
        onsetDetector.reset()
        pitchDetector?.reset()
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
    }

    private func setupTap() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            publishOnMain { [weak self] in
                self?.lastErrorMessage = AudioEngineError.noInputRouteAvailable.localizedDescription
            }
            throw AudioEngineError.noInputRouteAvailable
        }

        if pitchDetector == nil {
            pitchDetector = PitchDetector(sampleRate: inputFormat.sampleRate)
        }

        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?.pointee else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        let uptime = ProcessInfo.processInfo.systemUptime

        samples.withUnsafeBufferPointer { pointer in
            ringBuffer.append(contentsOf: pointer)
        }

        if shouldRecordAudio {
            try? recordingFile?.write(from: buffer)
        }

        analysisQueue.async { [weak self] in
            guard let self else { return }

            let onsetResult = self.onsetDetector.process(frame: samples, time: uptime)
            if onsetResult.isOnset {
                self.eventBus.publish(
                    onset: OnsetEvent(
                        time: uptime,
                        confidence: onsetResult.confidence,
                        source: .mic
                    )
                )
            }

            if let estimate = self.pitchDetector?.estimatePitch(frame: samples), estimate.confidence >= 0.55 {
                self.eventBus.publish(
                    pitch: PitchEvent(
                        time: uptime,
                        midiNote: estimate.midiNote,
                        confidence: estimate.confidence,
                        source: .mic
                    )
                )
            }
        }
    }

    private func makeRecordingFile() throws -> AVAudioFile {
        let format = engine.inputNode.inputFormat(forBus: 0)
        let folder = try recordingDirectory()
        let url = folder.appendingPathComponent("session-\(UUID().uuidString).caf")
        return try AVAudioFile(forWriting: url, settings: format.settings)
    }

    private func recordingDirectory() throws -> URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SessionRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        updateRouteName()
    }

    private func updateRouteName() {
        let route = AVAudioSession.sharedInstance().currentRoute
        let routeName = route.inputs.first?.portName ?? route.outputs.first?.portName ?? "Unknown"
        publishOnMain { [weak self] in
            self?.currentRouteName = routeName
        }
    }

    private nonisolated static func requestMicrophonePermissionFromSystem() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    private func publishOnMain(_ update: @escaping () -> Void) {
        if Thread.isMainThread {
            update()
            return
        }
        DispatchQueue.main.async(execute: update)
    }
}
