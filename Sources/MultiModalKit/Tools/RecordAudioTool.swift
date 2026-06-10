import AIToolKit
import Foundation
import FoundationModels

/// Controls a stateful microphone recording session.
///
/// A recording spans multiple invocations — `start`, then later `stop` — so the
/// tool holds the ``AudioRecorder`` it drives. Construct one recorder and reuse
/// the same `RecordAudioTool` instance for the lifetime of the registry.
public struct RecordAudioTool: Tool {
    public enum Action: String, Codable, Sendable, CaseIterable {
        case start
        case stop
        case cancel
        case status
    }

    @Generable
    public struct Input: Codable, Sendable {
        public var action: Action
        public var outputPath: String?

        public init(action: Action, outputPath: String? = nil) {
            self.action = action
            self.outputPath = outputPath
        }
    }

    @Generable
    public struct Output: Codable, Sendable {
        public var isRecording: Bool
        public var recordingPath: String?

        public init(isRecording: Bool, recordingPath: String? = nil) {
            self.isRecording = isRecording
            self.recordingPath = recordingPath
        }
    }

    public static let toolName = "record_audio"
    public static let toolDescription =
        "Controls microphone recording. Call with action 'start' to begin, "
        + "'stop' to finish and keep the file, 'cancel' to discard it, or "
        + "'status' to query. Recording continues across calls until stopped."

    public var name: String { Self.toolName }
    public var description: String { Self.toolDescription }

    private let recorder: AudioRecorder

    public init(recorder: AudioRecorder) {
        self.recorder = recorder
    }

    public func call(arguments input: Input) async throws -> Output {
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

extension RecordAudioTool.Action: Generable {
    public static var generationSchema: GenerationSchema {
        do {
            return try GenerationSchema(
                root: DynamicGenerationSchema(
                    name: "RecordAudioAction",
                    anyOf: Self.allCases.map(\.rawValue)
                ),
                dependencies: []
            )
        } catch {
            preconditionFailure("Invalid RecordAudioAction schema: \(error)")
        }
    }

    public init(_ content: GeneratedContent) throws {
        guard let rawValue = content.stringValue,
              let action = Self(rawValue: rawValue) else {
            throw GenericToolError(message: "Invalid record audio action.")
        }
        self = action
    }

    public var generatedContent: GeneratedContent { .string(rawValue) }
}
