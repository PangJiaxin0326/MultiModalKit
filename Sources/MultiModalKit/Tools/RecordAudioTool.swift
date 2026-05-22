import AIToolKit
import Foundation

/// Controls a stateful microphone recording session.
///
/// A recording spans multiple invocations — `start`, then later `stop` — so the
/// tool holds the ``AudioRecorder`` it drives. Construct one recorder and reuse
/// the same `RecordAudioTool` instance for the lifetime of the registry.
public struct RecordAudioTool: Tool {
    public enum Action: String, Codable, Sendable {
        case start
        case stop
        case cancel
        case status
    }

    public struct Input: Codable, Sendable {
        public var action: Action
        public var outputPath: String?

        public init(action: Action, outputPath: String? = nil) {
            self.action = action
            self.outputPath = outputPath
        }
    }

    public struct Output: Codable, Sendable {
        public var isRecording: Bool
        public var recordingPath: String?

        public init(isRecording: Bool, recordingPath: String? = nil) {
            self.isRecording = isRecording
            self.recordingPath = recordingPath
        }
    }

    public static let name = "record_audio"
    public static let description =
        "Controls microphone recording. Call with action 'start' to begin, "
        + "'stop' to finish and keep the file, 'cancel' to discard it, or "
        + "'status' to query. Recording continues across calls until stopped."
    public static let schema = ToolSchema.object(
        properties: [
            "action": .string(
                description: "One of: 'start', 'stop', 'cancel', 'status'."
            ),
            "outputPath": .string(
                description: "Optional absolute file path for the recording (used by 'start')."
            ),
        ],
        required: ["action"]
    )

    private let recorder: AudioRecorder

    public init(recorder: AudioRecorder) {
        self.recorder = recorder
    }

    public func invoke(_ input: Input, in context: ToolContext) async throws -> Output {
        switch input.action {
        case .start:
            let destination = input.outputPath.map { URL(filePath: $0) }
            _ = try await recorder.startRecordingWithPermission(to: destination)
        case .stop:
            _ = await recorder.stopRecording()
        case .cancel:
            await recorder.cancelRecording()
        case .status:
            break
        }

        return await MainActor.run {
            Output(
                isRecording: recorder.isRecording,
                recordingPath: recorder.currentRecordingURL?.path(percentEncoded: false)
            )
        }
    }
}
