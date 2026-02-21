import AVFoundation
import Foundation

@MainActor
final class IdeaRecorderEngine: NSObject, ObservableObject, AVAudioPlayerDelegate, AVCaptureFileOutputRecordingDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var lastRecordedURL: URL?
    @Published private(set) var lastRecordedVideoURL: URL?
    @Published private(set) var lastMetronomeReference: RecorderMetronomeReference?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?

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
        stopPlayback()
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
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
            isPlaying = true
        } catch {
            print("Playback failed: \(error)")
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
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
