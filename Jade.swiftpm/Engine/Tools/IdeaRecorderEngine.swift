import AVFoundation
import Foundation

@MainActor
final class IdeaRecorderEngine: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var recordingElapsed: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var lastRecordedURL: URL?
    @Published private(set) var lastMetronomeReference: RecorderMetronomeReference?

    @Published private(set) var currentPlaybackURL: URL?
    @Published private(set) var playbackCurrentTime: TimeInterval = 0
    @Published private(set) var playbackDuration: TimeInterval = 0
    @Published private(set) var playbackRate: Double = 1.0
    @Published private(set) var playbackSemitoneShift: Double = 0
    @Published private(set) var playbackErrorMessage: String?

    private var recorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?

    private let playbackEngine = AVAudioEngine()
    private let playbackNode = AVAudioPlayerNode()
    private let playbackTimePitch = AVAudioUnitTimePitch()
    private var playbackFile: AVAudioFile?
    private var playbackFileURL: URL?
    private var playbackStartFrame: AVAudioFramePosition = 0
    private var pausedPlaybackFrame: AVAudioFramePosition = 0
    private var playbackProgressTimer: Timer?
    private var playbackAnchorDate: Date?
    private var playbackAnchorTime: TimeInterval = 0
    private var didConfigurePlaybackGraph = false
    private var didConfigurePlaybackSession = false

    enum RecorderError: LocalizedError {
        case missingRecordingURL
        case missingPlaybackSelection
        case missingPlaybackFile
        case insufficientAudioPriority

        var errorDescription: String? {
            switch self {
            case .missingRecordingURL:
                return "No recording found yet."
            case .missingPlaybackSelection:
                return "Select a recording first."
            case .missingPlaybackFile:
                return "The selected recording file is unavailable."
            case .insufficientAudioPriority:
                return "Playback couldn’t start because audio is busy. Pause other audio and try again."
            }
        }
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func startRecording() throws {
        stopPlayback(resetSelection: true)
        playbackErrorMessage = nil
        didConfigurePlaybackSession = false
        recordingElapsed = 0
        stopRecordingTimer()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = try audioRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.prepareToRecord()
        recorder?.record()
        lastRecordedURL = url
        isRecording = true
        recordingStartedAt = Date()
        startRecordingTimer()
    }

    func captureMetronomeReference(from metronome: MetronomeEngine) {
        let meter = metronome.meter
        lastMetronomeReference = RecorderMetronomeReference(
            bpm: metronome.bpm,
            meterTop: meter.top,
            meterBottom: meter.bottom,
            subdivision: metronome.subdivision,
            metronomeRunningAtStart: metronome.isRunning,
            startUptime: ProcessInfo.processInfo.systemUptime,
            beatPhaseEstimate: 0
        )
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        updateRecordingElapsed()
        isRecording = false
        stopRecordingTimer()
        recordingStartedAt = nil
        didConfigurePlaybackSession = false
    }

    @discardableResult
    func playLatest() -> Bool {
        guard let url = lastRecordedURL else {
            playbackErrorMessage = RecorderError.missingRecordingURL.localizedDescription
            return false
        }
        return play(url: url)
    }

    @discardableResult
    func play(url: URL) -> Bool {
        do {
            try loadPlaybackFileIfNeeded(url)
            pausedPlaybackFrame = 0
            try startPlayback(from: pausedPlaybackFrame)
            playbackErrorMessage = nil
            return true
        } catch {
            playbackErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func togglePlayback(for url: URL) -> Bool {
        if currentPlaybackURL?.path == url.path {
            if isPlaying {
                pausePlayback()
                return true
            }
            return resumePlayback()
        }

        return play(url: url)
    }

    @discardableResult
    func togglePlayPause() -> Bool {
        if isPlaying {
            pausePlayback()
            return true
        }
        return resumePlayback()
    }

    func pausePlayback() {
        guard isPlaying else { return }
        updatePlaybackProgress()
        playbackNode.pause()
        isPlaying = false
        playbackAnchorDate = nil
        stopPlaybackProgressTimer()
    }

    @discardableResult
    func resumePlayback() -> Bool {
        guard let url = currentPlaybackURL else {
            playbackErrorMessage = RecorderError.missingPlaybackSelection.localizedDescription
            return false
        }

        do {
            try loadPlaybackFileIfNeeded(url)
            guard let file = playbackFile else {
                playbackErrorMessage = RecorderError.missingPlaybackFile.localizedDescription
                return false
            }
            if pausedPlaybackFrame >= file.length {
                pausedPlaybackFrame = 0
            }
            try startPlayback(from: pausedPlaybackFrame)
            playbackErrorMessage = nil
            return true
        } catch {
            playbackErrorMessage = error.localizedDescription
            return false
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let file = playbackFile else { return }
        let clamped = max(0, min(playbackDuration, seconds))
        let sampleRate = file.processingFormat.sampleRate
        let frame = AVAudioFramePosition(clamped * sampleRate)
        pausedPlaybackFrame = max(0, min(frame, file.length))
        playbackCurrentTime = clamped

        guard isPlaying else { return }

        do {
            try startPlayback(from: pausedPlaybackFrame)
        } catch {
            print("Seek failed: \(error)")
        }
    }

    func setPlaybackRate(_ value: Double) {
        let clamped = max(0.5, min(2.0, value))
        guard abs(clamped - playbackRate) > 0.000_1 else { return }
        if isPlaying {
            updatePlaybackProgress()
            playbackAnchorDate = Date()
            playbackAnchorTime = playbackCurrentTime
        }
        playbackRate = clamped
        playbackTimePitch.rate = Float(clamped)
    }

    func setPlaybackSemitoneShift(_ value: Double) {
        let clamped = max(-12, min(12, value)).rounded()
        guard abs(clamped - playbackSemitoneShift) > 0.000_1 else { return }
        playbackSemitoneShift = clamped
        playbackTimePitch.pitch = Float(clamped * 100)
    }

    func stopPlayback(resetSelection: Bool = false) {
        playbackNode.stop()
        isPlaying = false
        stopPlaybackProgressTimer()
        playbackAnchorDate = nil
        playbackAnchorTime = 0

        pausedPlaybackFrame = 0
        playbackStartFrame = 0
        playbackCurrentTime = 0

        if resetSelection {
            currentPlaybackURL = nil
            playbackFile = nil
            playbackFileURL = nil
            playbackDuration = 0
        }

        didConfigurePlaybackSession = false
    }

    private func loadPlaybackFileIfNeeded(_ url: URL) throws {
        if playbackFileURL?.path == url.path,
           playbackFile != nil,
           currentPlaybackURL?.path == url.path {
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RecorderError.missingPlaybackFile
        }

        try configurePlaybackSession()
        try configurePlaybackGraphIfNeeded()

        let file = try AVAudioFile(forReading: url)
        playbackFile = file
        playbackFileURL = url
        currentPlaybackURL = url

        pausedPlaybackFrame = 0
        playbackStartFrame = 0
        playbackCurrentTime = 0
        playbackAnchorDate = nil
        playbackAnchorTime = 0
        playbackDuration = Double(file.length) / file.processingFormat.sampleRate
    }

    private func configurePlaybackSession() throws {
        if didConfigurePlaybackSession { return }

        let session = AVAudioSession.sharedInstance()
        do {
            // Stay compatible with live input/metronome engines that may already own session policy.
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true)
            didConfigurePlaybackSession = true
            return
        } catch {
            if isInsufficientPriorityError(error) {
                // Fallback: if category switch is blocked, try a lightweight activation only.
                do {
                    try session.setActive(true)
                    didConfigurePlaybackSession = true
                    return
                } catch {
                    if isInsufficientPriorityError(error) {
                        // Last fallback: proceed without forcing activation; another app engine
                        // may already own an active session that is still usable for output.
                        didConfigurePlaybackSession = true
                        return
                    }
                    throw error
                }
            }
            throw error
        }
    }

    private func configurePlaybackGraphIfNeeded() throws {
        guard !didConfigurePlaybackGraph else {
            if !playbackEngine.isRunning {
                try playbackEngine.start()
            }
            return
        }

        playbackEngine.attach(playbackNode)
        playbackEngine.attach(playbackTimePitch)
        playbackEngine.connect(playbackNode, to: playbackTimePitch, format: nil)
        playbackEngine.connect(playbackTimePitch, to: playbackEngine.mainMixerNode, format: nil)

        playbackTimePitch.rate = Float(playbackRate)
        playbackTimePitch.pitch = Float(playbackSemitoneShift * 100)

        try playbackEngine.start()
        didConfigurePlaybackGraph = true
    }

    private func startPlayback(from frame: AVAudioFramePosition) throws {
        guard let file = playbackFile else { return }

        try configurePlaybackSession()
        try configurePlaybackGraphIfNeeded()
        if !playbackEngine.isRunning {
            try playbackEngine.start()
        }

        let safeFrame = max(0, min(frame, file.length))
        let remainingFrames = max(0, file.length - safeFrame)
        guard remainingFrames > 0 else {
            pausedPlaybackFrame = file.length
            playbackCurrentTime = playbackDuration
            isPlaying = false
            stopPlaybackProgressTimer()
            return
        }

        playbackNode.stop()
        playbackStartFrame = safeFrame
        pausedPlaybackFrame = safeFrame
        let startTime = Double(safeFrame) / file.processingFormat.sampleRate
        playbackCurrentTime = startTime
        playbackAnchorTime = startTime
        playbackAnchorDate = Date()

        let maxCount = AVAudioFramePosition(UInt32.max)
        let frameCount = AVAudioFrameCount(min(remainingFrames, maxCount))

        playbackNode.scheduleSegment(
            file,
            startingFrame: safeFrame,
            frameCount: frameCount,
            at: nil
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handlePlaybackFinished()
            }
        }

        playbackNode.play()
        isPlaying = true
        startPlaybackProgressTimer()
    }

    private func handlePlaybackFinished() {
        guard let file = playbackFile else {
            isPlaying = false
            stopPlaybackProgressTimer()
            playbackAnchorDate = nil
            return
        }

        pausedPlaybackFrame = file.length
        playbackCurrentTime = playbackDuration
        playbackAnchorDate = nil
        isPlaying = false
        stopPlaybackProgressTimer()
    }

    private func currentPlaybackFrameFromNode() -> AVAudioFramePosition? {
        guard let nodeTime = playbackNode.lastRenderTime,
              let playerTime = playbackNode.playerTime(forNodeTime: nodeTime) else {
            return nil
        }

        return playbackStartFrame + AVAudioFramePosition(playerTime.sampleTime)
    }

    private func updatePlaybackProgress() {
        guard isPlaying, let file = playbackFile else { return }

        let frame: AVAudioFramePosition = {
            if let nodeFrame = currentPlaybackFrameFromNode() {
                return nodeFrame
            }
            guard let anchorDate = playbackAnchorDate else { return pausedPlaybackFrame }
            let elapsed = max(0, Date().timeIntervalSince(anchorDate))
            let estimatedTime = min(playbackDuration, playbackAnchorTime + (elapsed * playbackRate))
            return AVAudioFramePosition(estimatedTime * file.processingFormat.sampleRate)
        }()
        pausedPlaybackFrame = max(0, min(frame, file.length))
        playbackCurrentTime = min(playbackDuration, Double(pausedPlaybackFrame) / file.processingFormat.sampleRate)
    }

    private func startPlaybackProgressTimer() {
        stopPlaybackProgressTimer()

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updatePlaybackProgress()
        }
        playbackProgressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPlaybackProgressTimer() {
        playbackProgressTimer?.invalidate()
        playbackProgressTimer = nil
    }

    private func startRecordingTimer() {
        stopRecordingTimer()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateRecordingElapsed()
        }
        recordingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func updateRecordingElapsed() {
        guard let recordingStartedAt else { return }
        recordingElapsed = max(0, Date().timeIntervalSince(recordingStartedAt))
    }

    private func recordingFolderURL() throws -> URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("IdeaSnippets", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func audioRecordingURL() throws -> URL {
        try recordingFolderURL().appendingPathComponent("idea-\(UUID().uuidString).m4a")
    }

    private func isInsufficientPriorityError(_ error: Error) -> Bool {
        let nsError = error as NSError

        if let code = AVAudioSession.ErrorCode(rawValue: nsError.code),
           code == .insufficientPriority {
            return true
        }

        // OSStatus '!pri' (561017449) reported by lower-level audio APIs.
        return nsError.code == 561_017_449
    }
}
