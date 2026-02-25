import AVFoundation
import Foundation

@MainActor
final class IdeaRecorderEngine: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var lastRecordedURL: URL?
    @Published private(set) var lastRecordedVideoURL: URL?
    @Published private(set) var lastMetronomeReference: RecorderMetronomeReference?

    @Published private(set) var currentPlaybackURL: URL?
    @Published private(set) var playbackCurrentTime: TimeInterval = 0
    @Published private(set) var playbackDuration: TimeInterval = 0
    @Published private(set) var playbackRate: Double = 1.0
    @Published private(set) var playbackSemitoneShift: Double = 0

    private var recorder: AVAudioRecorder?
    private var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?

    private let playbackEngine = AVAudioEngine()
    private let playbackNode = AVAudioPlayerNode()
    private let playbackTimePitch = AVAudioUnitTimePitch()
    private var playbackFile: AVAudioFile?
    private var playbackFileURL: URL?
    private var playbackStartFrame: AVAudioFramePosition = 0
    private var pausedPlaybackFrame: AVAudioFramePosition = 0
    private var playbackProgressTimer: Timer?
    private var didConfigurePlaybackGraph = false

    enum RecorderError: LocalizedError {
        case cameraUnavailable
        case cannotAddCameraInput
        case cannotAddAudioInput
        case cannotAddMovieOutput

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable:
                return "Camera is unavailable on this device."
            case .cannotAddCameraInput:
                return "Unable to configure camera input."
            case .cannotAddAudioInput:
                return "Unable to configure microphone input for video."
            case .cannotAddMovieOutput:
                return "Unable to configure video recording output."
            }
        }
    }

    var isVideoCaptureAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            || AVCaptureDevice.default(for: .video) != nil
    }

    func requestPermission(includeVideo: Bool) async -> Bool {
        let micGranted = await withCheckedContinuation { continuation in
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
        guard micGranted else { return false }

        guard includeVideo else { return true }
        guard isVideoCaptureAvailable else { return false }

        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func startRecording(withVideo: Bool) throws {
        stopPlayback(resetSelection: true)
        if withVideo {
            try startVideoRecording()
        } else {
            try startAudioRecording()
        }
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

    private func startAudioRecording() throws {
        tearDownVideoCapture()

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
        recorder?.record()
        lastRecordedURL = url
        lastRecordedVideoURL = nil
        isRecording = true
    }

    private func startVideoRecording() throws {
        recorder?.stop()
        recorder = nil

        guard isVideoCaptureAvailable else {
            throw RecorderError.cameraUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let capture = AVCaptureSession()
        capture.beginConfiguration()
        if capture.canSetSessionPreset(.high) {
            capture.sessionPreset = .high
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video) else {
            throw RecorderError.cameraUnavailable
        }

        let videoInput = try AVCaptureDeviceInput(device: camera)
        guard capture.canAddInput(videoInput) else {
            throw RecorderError.cannotAddCameraInput
        }
        capture.addInput(videoInput)

        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            guard capture.canAddInput(audioInput) else {
                throw RecorderError.cannotAddAudioInput
            }
            capture.addInput(audioInput)
        }

        let output = AVCaptureMovieFileOutput()
        guard capture.canAddOutput(output) else {
            throw RecorderError.cannotAddMovieOutput
        }
        capture.addOutput(output)

        capture.commitConfiguration()
        captureSession = capture
        movieOutput = output

        let url = try videoRecordingURL()
        try? FileManager.default.removeItem(at: url)
        lastRecordedVideoURL = nil
        lastRecordedURL = nil

        capture.startRunning()
        output.startRecording(to: url, recordingDelegate: self)
        isRecording = true
    }

    func stopRecording() {
        if let output = movieOutput, output.isRecording {
            output.stopRecording()
            isRecording = false
            return
        }

        recorder?.stop()
        recorder = nil
        isRecording = false
    }

    func playLatest() {
        guard let url = lastRecordedURL else { return }
        play(url: url)
    }

    func play(url: URL) {
        do {
            try loadPlaybackFileIfNeeded(url)
            pausedPlaybackFrame = 0
            try startPlayback(from: pausedPlaybackFrame)
        } catch {
            print("Playback failed: \(error)")
        }
    }

    func togglePlayback(for url: URL) {
        if currentPlaybackURL?.path == url.path {
            if isPlaying {
                pausePlayback()
            } else {
                resumePlayback()
            }
            return
        }

        play(url: url)
    }

    func togglePlayPause() {
        if isPlaying {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }

    func pausePlayback() {
        guard isPlaying else { return }
        updatePlaybackProgress()
        playbackNode.pause()
        isPlaying = false
        stopPlaybackProgressTimer()
    }

    func resumePlayback() {
        guard let url = currentPlaybackURL else { return }

        do {
            try loadPlaybackFileIfNeeded(url)
            guard let file = playbackFile else { return }
            if pausedPlaybackFrame >= file.length {
                pausedPlaybackFrame = 0
            }
            try startPlayback(from: pausedPlaybackFrame)
        } catch {
            print("Resume playback failed: \(error)")
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

        pausedPlaybackFrame = 0
        playbackStartFrame = 0
        playbackCurrentTime = 0

        if resetSelection {
            currentPlaybackURL = nil
            playbackFile = nil
            playbackFileURL = nil
            playbackDuration = 0
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.tearDownVideoCapture()
            self.isRecording = false

            if error == nil {
                self.lastRecordedVideoURL = outputFileURL
            }
        }
    }

    private func loadPlaybackFileIfNeeded(_ url: URL) throws {
        if playbackFileURL?.path == url.path,
           playbackFile != nil,
           currentPlaybackURL?.path == url.path {
            return
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
        playbackDuration = Double(file.length) / file.processingFormat.sampleRate
    }

    private func configurePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
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
            return
        }

        pausedPlaybackFrame = file.length
        playbackCurrentTime = playbackDuration
        isPlaying = false
        stopPlaybackProgressTimer()
    }

    private func currentPlaybackFrame() -> AVAudioFramePosition {
        guard let nodeTime = playbackNode.lastRenderTime,
              let playerTime = playbackNode.playerTime(forNodeTime: nodeTime) else {
            return pausedPlaybackFrame
        }

        return playbackStartFrame + AVAudioFramePosition(playerTime.sampleTime)
    }

    private func updatePlaybackProgress() {
        guard isPlaying, let file = playbackFile else { return }

        let frame = currentPlaybackFrame()
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

    private func recordingFolderURL() throws -> URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("IdeaSnippets", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func audioRecordingURL() throws -> URL {
        try recordingFolderURL().appendingPathComponent("idea-\(UUID().uuidString).m4a")
    }

    private func videoRecordingURL() throws -> URL {
        try recordingFolderURL().appendingPathComponent("idea-\(UUID().uuidString).mov")
    }

    private func tearDownVideoCapture() {
        if let captureSession, captureSession.isRunning {
            captureSession.stopRunning()
        }
        movieOutput = nil
        captureSession = nil
    }
}
