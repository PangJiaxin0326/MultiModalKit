import AIToolKit
import Foundation
import FoundationModels

/// Transcribes spoken audio from a file into text.
public struct TranscribeAudioFileTool: Tool {
    @Generable
    public struct Input: Codable, Sendable {
        public var audioPath: String
        public var localeIdentifier: String?

        public init(audioPath: String, localeIdentifier: String? = nil) {
            self.audioPath = audioPath
            self.localeIdentifier = localeIdentifier
        }
    }

    @Generable
    public struct Output: Codable, Sendable {
        public var transcript: String

        public init(transcript: String) {
            self.transcript = transcript
        }
    }

    public static let toolName = "transcribe_audio_file"
    public static let toolDescription =
        "Transcribes spoken audio from an audio file on disk into text "
        + "using on-device speech recognition."

    public var name: String { Self.toolName }
    public var description: String { Self.toolDescription }

    public init() {}

    public func call(arguments input: Input) async throws -> Output {
        let service = SpeechTranscriptionService()
        let locale = input.localeIdentifier.map { Locale(identifier: $0) } ?? .current
        let result = try await service.transcribeAudioFile(
            at: URL(filePath: input.audioPath),
            locale: locale
        )
        return Output(transcript: result.plainText)
    }
}
