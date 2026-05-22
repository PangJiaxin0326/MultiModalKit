import AIToolKit
import Foundation

/// Extracts text from an image file using on-device OCR.
public struct RecognizeTextTool: Tool {
    public struct Input: Codable, Sendable {
        public var imagePath: String
        public var recognitionLevel: String?
        public var languages: [String]?

        public init(
            imagePath: String,
            recognitionLevel: String? = nil,
            languages: [String]? = nil
        ) {
            self.imagePath = imagePath
            self.recognitionLevel = recognitionLevel
            self.languages = languages
        }
    }

    public struct Output: Codable, Sendable {
        public struct Observation: Codable, Sendable {
            public var text: String
            public var confidence: Float

            public init(text: String, confidence: Float) {
                self.text = text
                self.confidence = confidence
            }
        }

        public var fullText: String
        public var observations: [Observation]

        public init(fullText: String, observations: [Observation]) {
            self.fullText = fullText
            self.observations = observations
        }
    }

    public static let name = "recognize_text"
    public static let description =
        "Extracts text from an image file on disk using on-device OCR."
    public static let schema = ToolSchema.object(
        properties: [
            "imagePath": .string(
                description: "Absolute file path to the image to read text from."
            ),
            "recognitionLevel": .string(
                description: "Accuracy mode: 'fast' or 'accurate' (the default)."
            ),
            "languages": .array(
                of: .string(description: "A BCP-47 language tag, e.g. 'en-US'.")
            ),
        ],
        required: ["imagePath"]
    )

    public init() {}

    public func invoke(_ input: Input, in context: ToolContext) async throws -> Output {
        var configuration = OCRConfiguration()
        if let level = input.recognitionLevel?.lowercased() {
            configuration.recognitionLevel = level == "fast" ? .fast : .accurate
        }
        if let languages = input.languages, !languages.isEmpty {
            configuration.automaticallyDetectsLanguage = false
            configuration.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }
        }

        let processor = VisionOCRProcessor(configuration: configuration)
        let result = try await processor.recognizeText(in: URL(filePath: input.imagePath))
        return Output(
            fullText: result.fullText,
            observations: result.observations.map {
                Output.Observation(text: $0.text, confidence: $0.confidence)
            }
        )
    }
}
