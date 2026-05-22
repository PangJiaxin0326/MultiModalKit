import AIToolKit
import Foundation

/// Captures one spoken utterance from the microphone and transcribes it.
public struct TranscribeSpeechTool: Tool {
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

    public struct Output: Codable, Sendable {
        public var transcript: String

        public init(transcript: String) {
            self.transcript = transcript
        }
    }

    public static let name = "transcribe_speech"
    public static let description =
        "Listens to the microphone and transcribes a single spoken utterance, "
        + "ending after a sustained pause in speech."
    public static let schema = ToolSchema.object(
        properties: [
            "localeIdentifier": .string(
                description: "Optional BCP-47 locale, e.g. 'en-US'. Defaults to the device locale."
            ),
            "silenceSeconds": ToolSchema(json: [
                "type": "number",
                "description": "Seconds of silence after speech that ends capture.",
            ]),
            "maxWaitSeconds": ToolSchema(json: [
                "type": "number",
                "description": "Give up and return after this long if no speech is heard.",
            ]),
        ],
        required: []
    )

    public init() {}

    public func invoke(_ input: Input, in context: ToolContext) async throws -> Output {
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
