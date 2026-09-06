import AVFoundation
import Combine
import Foundation

public enum AudioRecordingFormat: Equatable, Sendable {
    case m4a
    case wav

    var fileExtension: String {
        switch self {
        case .m4a:
            "m4a"
        case .wav:
            "wav"
        }
    }

    var formatID: AudioFormatID {
        switch self {
        case .m4a:
            kAudioFormatMPEG4AAC
        case .wav:
            kAudioFormatLinearPCM
        }
    }
}

public struct AudioRecordingConfiguration: Equatable, Sendable {
    public var format: AudioRecordingFormat
    public var sampleRate: Double
    public var channelCount: Int
    public var quality: AVAudioQuality

    public init(
        format: AudioRecordingFormat = .m4a,
        sampleRate: Double = 44_100,
        channelCount: Int = 1,
        quality: AVAudioQuality = .high
    ) {
        self.format = format
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.quality = quality
    }

    var recorderSettings: [String: Any] {
        [
            AVFormatIDKey: format.formatID,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderAudioQualityKey: quality.rawValue,
        ]
    }
}

@MainActor
public final class AudioRecorder: NSObject, ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var currentRecordingURL: URL?
    @Published public private(set) var averagePowerDecibels: Float = -60
    @Published public private(set) var peakPowerDecibels: Float = -60
    @Published public private(set) var averagePowerLevel: Double = 0
    @Published public private(set) var peakPowerLevel: Double = 0

    private var recorder: AVAudioRecorder?
    private var isStarting = false
    private var startCancelled = false
    private var meteringTask: Task<Void, Never>?

    private static let silentPower: Float = -60

    public override init() {
        super.init()
    }

    @discardableResult
    public func startRecording(
        to url: URL? = nil,
        configuration: AudioRecordingConfiguration = AudioRecordingConfiguration()
    ) throws -> URL {
        guard !isStarting else {
            throw MultiModalKitError.recordingFailed("A recording is already starting.")
        }
        if let inProgressURL = try recordingInProgressURL() {
            return inProgressURL
        }
        let destinationURL = url ?? Self.temporaryRecordingURL(format: configuration.format)
        let shouldRemoveFileOnFailure = url == nil

        do {
            let recorder = try Self.startConfiguredRecorderSync(
                destinationURL: destinationURL,
                configuration: configuration
            )
            attach(recorder: recorder, url: destinationURL)
            return destinationURL
        } catch {
            handleStartFailure(destinationURL: destinationURL, removeFile: shouldRemoveFileOnFailure)
            throw error
        }
    }

    @discardableResult
    public func startRecordingWithPermission(
        to url: URL? = nil,
        configuration: AudioRecordingConfiguration = AudioRecordingConfiguration()
    ) async throws -> URL {
        guard !isStarting else {
            throw MultiModalKitError.recordingFailed("A recording is already starting.")
        }
        if let inProgressURL = try recordingInProgressURL() {
            return inProgressURL
        }
        isStarting = true
        startCancelled = false
        defer { isStarting = false }
        try Task.checkCancellation()
        try await PermissionCenter.require(.microphone)
        try Task.checkCancellation()
        if startCancelled { throw CancellationError() }
        let destinationURL = url ?? Self.temporaryRecordingURL(format: configuration.format)
        let shouldRemoveFileOnFailure = url == nil

        do {
            let recorder = try await Self.startConfiguredRecorder(
                destinationURL: destinationURL,
                configuration: configuration
            )
            guard !Task.isCancelled, !startCancelled else {
                recorder.stop()
                throw CancellationError()
            }
            attach(recorder: recorder, url: destinationURL)
            return destinationURL
        } catch {
            handleStartFailure(destinationURL: destinationURL, removeFile: shouldRemoveFileOnFailure)
            throw error
        }
    }

    private func recordingInProgressURL() throws -> URL? {
        guard isRecording else { return nil }
        if let currentRecordingURL {
            return currentRecordingURL
        }
        throw MultiModalKitError.recordingFailed(
            MultiModalKitLocalization.string("A recording is already in progress.")
        )
    }

    private func attach(recorder: sending AVAudioRecorder, url: URL) {
        self.recorder = recorder
        currentRecordingURL = url
        isRecording = true
        startMetering()
    }

    private func handleStartFailure(destinationURL: URL, removeFile: Bool) {
        Self.deactivateAudioSessionIfNeeded()
        if removeFile {
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }

    @discardableResult
    public func stopRecording() -> URL? {
        startCancelled = true
        guard isRecording else {
            return currentRecordingURL
        }

        stopMetering(resetLevels: true)
        recorder?.stop()
        recorder = nil
        isRecording = false
        Self.deactivateAudioSessionIfNeeded()
        return currentRecordingURL
    }

    public func cancelRecording(removeFile: Bool = true) {
        startCancelled = true
        let url = currentRecordingURL
        stopMetering(resetLevels: true)
        recorder?.stop()
        recorder = nil
        currentRecordingURL = nil
        isRecording = false
        Self.deactivateAudioSessionIfNeeded()

        if removeFile, let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func startMetering() {
        stopMetering(resetLevels: false)
        refreshMeters()
        meteringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                self?.refreshMeters()
            }
        }
    }

    private func stopMetering(resetLevels: Bool) {
        meteringTask?.cancel()
        meteringTask = nil
        if resetLevels {
            resetMeters()
        }
    }

    private func refreshMeters() {
        guard let recorder, isRecording else {
            resetMeters()
            return
        }

        recorder.updateMeters()
        averagePowerDecibels = max(Self.silentPower, recorder.averagePower(forChannel: 0))
        peakPowerDecibels = max(Self.silentPower, recorder.peakPower(forChannel: 0))
        averagePowerLevel = Self.normalizedPower(from: averagePowerDecibels)
        peakPowerLevel = Self.normalizedPower(from: peakPowerDecibels)
    }

    private func resetMeters() {
        averagePowerDecibels = Self.silentPower
        peakPowerDecibels = Self.silentPower
        averagePowerLevel = 0
        peakPowerLevel = 0
    }

    private static func normalizedPower(from decibels: Float) -> Double {
        guard decibels.isFinite else { return 0 }
        let clamped = min(0, max(silentPower, decibels))
        let normalized = Double((clamped - silentPower) / -silentPower)
        return sqrt(normalized)
    }

    private static func temporaryRecordingURL(format: AudioRecordingFormat) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString)")
            .appendingPathExtension(format.fileExtension)
    }

    #if os(iOS) || os(visionOS)
    /// `setCategory`/`setActive` block the calling thread, so all session work
    /// runs on this serial queue: activations stay ordered with respect to
    /// fire-and-forget deactivations without touching the main thread.
    private nonisolated static let audioSessionQueue = DispatchQueue(
        label: "MultiModalKit.AudioRecorder.AudioSession"
    )

    private nonisolated static func configureAndActivateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    #endif

    /// Creates, prepares, and starts the recorder. `prepareToRecord()`/`record()`
    /// implicitly activate the audio session, so this must never run on the main
    /// thread; both entry points dispatch it onto `audioSessionQueue`.
    private nonisolated static func makeAndStartRecorder(
        destinationURL: URL,
        configuration: AudioRecordingConfiguration
    ) throws -> sending AVAudioRecorder {
        #if os(iOS) || os(visionOS)
        try configureAndActivateSession()
        #endif
        let recorder = try AVAudioRecorder(url: destinationURL, settings: configuration.recorderSettings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw MultiModalKitError.recordingFailed(
                MultiModalKitLocalization.string("AVAudioRecorder did not start.")
            )
        }
        return recorder
    }

    private nonisolated static func startConfiguredRecorder(
        destinationURL: URL,
        configuration: AudioRecordingConfiguration
    ) async throws -> sending AVAudioRecorder {
        #if os(iOS) || os(visionOS)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAudioRecorder, any Error>) in
            audioSessionQueue.async {
                continuation.resume(with: Result {
                    try makeAndStartRecorder(destinationURL: destinationURL, configuration: configuration)
                })
            }
        }
        #else
        return try makeAndStartRecorder(destinationURL: destinationURL, configuration: configuration)
        #endif
    }

    private nonisolated static func startConfiguredRecorderSync(
        destinationURL: URL,
        configuration: AudioRecordingConfiguration
    ) throws -> sending AVAudioRecorder {
        #if os(iOS) || os(visionOS)
        return try audioSessionQueue.sync {
            try makeAndStartRecorder(destinationURL: destinationURL, configuration: configuration)
        }
        #else
        return try makeAndStartRecorder(destinationURL: destinationURL, configuration: configuration)
        #endif
    }

    private nonisolated static func deactivateAudioSessionIfNeeded() {
        #if os(iOS) || os(visionOS)
        audioSessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }

    deinit {
        meteringTask?.cancel()
    }
}
