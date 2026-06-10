import AIToolKit
import Foundation
import FoundationModels

/// Extracts text from an image file using on-device OCR.
public struct RecognizeTextTool: Tool {
    @Generable
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

    @Generable
    public struct Output: Codable, Sendable {
        @Generable
        public struct Observation: Codable, Sendable {
            public var text: String
            public var confidence: Double

            public init(text: String, confidence: Double) {
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

    public static let toolName = "recognize_text"
    public static let toolDescription =
        "Extracts text from an image file on disk using on-device OCR."

    public var name: String { Self.toolName }
    public var description: String { Self.toolDescription }

    public init() {}

    public func call(arguments input: Input) async throws -> Output {
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
                Output.Observation(text: $0.text, confidence: Double($0.confidence))
            }
        )
    }
}
