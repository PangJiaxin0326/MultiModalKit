import AIToolKit
import Foundation
import FoundationModels

/// Speaks text aloud using on-device text-to-speech.
public struct SpeakTextTool: Tool {
    @Generable
    public struct Input: Codable, Sendable {
        public var text: String

        public init(text: String) {
            self.text = text
        }
    }

    @Generable
    public struct Output: Codable, Sendable {
        public var spokenText: String

        public init(spokenText: String) {
            self.spokenText = spokenText
        }
    }

    public static let toolName = "speak_text"
    public static let toolDescription =
        "Speaks the given text aloud with on-device text-to-speech. "
        + "Returns once playback finishes."

    public var name: String { Self.toolName }
    public var description: String { Self.toolDescription }

    public init() {}

    public func call(arguments input: Input) async throws -> Output {
        let synthesizer = await SpeechSynthesizer()
        await synthesizer.speak(input.text)
        return Output(spokenText: input.text)
    }
}
