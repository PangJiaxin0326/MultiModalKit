import AIToolKit
import Foundation
import FoundationModels

/// Captures one spoken utterance from the microphone and transcribes it.
public struct TranscribeSpeechTool: Tool {
    @Generable
    public struct Input: Codable, Sendable {
        public var localeIdentifier: String?
        public var silenceSeconds: Double?
        public var maxWaitSeconds: Double?

        public init(
            localeIdentifier: String? = nil,
            silenceSeconds: Double? = nil,
            maxWaitSeconds: Double? = nil
        ) {
            self.localeIdentifier = localeIdentifier
            self.silenceSeconds = silenceSeconds
            self.maxWaitSeconds = maxWaitSeconds
        }
    }

    @Generable
    public struct Output: Codable, Sendable {
        public var transcript: String

        public init(transcript: String) {
            self.transcript = transcript
        }
    }

    public static let toolName = "transcribe_speech"
    public static let toolDescription =
        "Listens to the microphone and transcribes a single spoken utterance, "
        + "ending after a sustained pause in speech."

    public var name: String { Self.toolName }
    public var description: String { Self.toolDescription }

    public init() {}

    public func call(arguments input: Input) async throws -> Output {
        var configuration = LiveSpeechConfiguration()
        if let identifier = input.localeIdentifier {
            configuration.locale = Locale(identifier: identifier)
        }
        if let silenceSeconds = input.silenceSeconds {
            configuration.silenceDuration = .seconds(silenceSeconds)
        }
        if let maxWaitSeconds = input.maxWaitSeconds {
            configuration.noSpeechTimeout = .seconds(maxWaitSeconds)
        }

        let session = await LiveSpeechSession(configuration: configuration)
        try await session.start()
        do {
            try await session.awaitSilence()
        } catch {
            await session.cancel()
            throw error
        }
        let transcript = await session.finish()
        return Output(transcript: transcript)
    }
}
