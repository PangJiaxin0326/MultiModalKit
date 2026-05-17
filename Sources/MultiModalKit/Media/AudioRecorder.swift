@preconcurrency import AVFoundation
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

    private var recorder: AVAudioRecorder?

    public override init() {
        super.init()
    }

    @discardableResult
    public func startRecording(
        to url: URL? = nil,
        configuration: AudioRecordingConfiguration = AudioRecordingConfiguration()
    ) throws -> URL {
        guard !isRecording else {
            if let currentRecordingURL {
                return currentRecordingURL
            }
            throw MultiModalKitError.recordingFailed("A recording is already in progress.")
        }

        let destinationURL = url ?? Self.temporaryRecordingURL(format: configuration.format)
        try Self.prepareAudioSessionIfNeeded()

        let recorder = try AVAudioRecorder(url: destinationURL, settings: configuration.recorderSettings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw MultiModalKitError.recordingFailed("AVAudioRecorder did not start.")
        }

        self.recorder = recorder
        currentRecordingURL = destinationURL
        isRecording = true
        return destinationURL
    }

    @discardableResult
    public func startRecordingWithPermission(
        to url: URL? = nil,
        configuration: AudioRecordingConfiguration = AudioRecordingConfiguration()
    ) async throws -> URL {
        try await PermissionCenter.require(.microphone)
        return try startRecording(to: url, configuration: configuration)
    }

    @discardableResult
    public func stopRecording() -> URL? {
        guard isRecording else {
            return currentRecordingURL
        }

        recorder?.stop()
        recorder = nil
        isRecording = false
        Self.deactivateAudioSessionIfNeeded()
        return currentRecordingURL
    }

    public func cancelRecording(removeFile: Bool = true) {
        let url = currentRecordingURL
        recorder?.stop()
        recorder = nil
        currentRecordingURL = nil
        isRecording = false
        Self.deactivateAudioSessionIfNeeded()

        if removeFile, let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func temporaryRecordingURL(format: AudioRecordingFormat) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString)")
            .appendingPathExtension(format.fileExtension)
    }

    private static func prepareAudioSessionIfNeeded() throws {
        #if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    private static func deactivateAudioSessionIfNeeded() {
        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
