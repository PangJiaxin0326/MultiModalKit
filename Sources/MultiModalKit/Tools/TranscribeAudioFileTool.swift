import AIToolKit
import Foundation

/// Transcribes spoken audio from a file into text.
public struct TranscribeAudioFileTool: Tool {
    public struct Input: Codable, Sendable {
        public var audioPath: String
        public var localeIdentifier: String?

        public init(audioPath: String, localeIdentifier: String? = nil) {
            self.audioPath = audioPath
            self.localeIdentifier = localeIdentifier
        }
    }

    public struct Output: Codable, Sendable {
        public var transcript: String

        public init(transcript: String) {
            self.transcript = transcript
        }
    }

    public static let name = "transcribe_audio_file"
    public static let description =
        "Transcribes spoken audio from an audio file on disk into text "
        + "using on-device speech recognition."
    public static let inputSchema = ToolSchema.object(
        properties: [
            "audioPath": .string(
                description: "Absolute file path to the audio file (m4a, wav, ...)."
            ),
            "localeIdentifier": .string(
                description: "Optional BCP-47 locale, e.g. 'en-US'. Defaults to the device locale."
            ),
        ],
        required: ["audioPath"]
    )

    public init() {}

    public func call(_ input: Input, in context: ToolContext) async throws -> Output {
        let service = SpeechTranscriptionService()
        let locale = input.localeIdentifier.map { Locale(identifier: $0) } ?? .current
        let result = try await service.transcribeAudioFile(
            at: URL(filePath: input.audioPath),
            locale: locale
        )
        return Output(transcript: result.plainText)
    }
}
