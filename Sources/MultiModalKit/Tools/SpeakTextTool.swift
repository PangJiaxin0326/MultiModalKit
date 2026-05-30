import AIToolKit
import Foundation

/// Speaks text aloud using on-device text-to-speech.
public struct SpeakTextTool: Tool {
    public struct Input: Codable, Sendable {
        public var text: String

        public init(text: String) {
            self.text = text
        }
    }

    public struct Output: Codable, Sendable {
        public var spokenText: String

        public init(spokenText: String) {
            self.spokenText = spokenText
        }
    }

    public static let name = "speak_text"
    public static let description =
        "Speaks the given text aloud with on-device text-to-speech. "
        + "Returns once playback finishes."
    public static let inputSchema = ToolSchema.object(
        properties: [
            "text": .string(description: "The text to speak aloud."),
        ],
        required: ["text"]
    )

    public init() {}

    public func call(_ input: Input, in context: ToolContext) async throws -> Output {
        let synthesizer = await SpeechSynthesizer()
        await synthesizer.speak(input.text)
        return Output(spokenText: input.text)
    }
}
