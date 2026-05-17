import CoreGraphics
import Foundation
import ImageIO
import Vision

public struct OCRConfiguration: Equatable, Sendable {
    public var recognitionLevel: RecognizeTextRequest.RecognitionLevel
    public var automaticallyDetectsLanguage: Bool
    public var recognitionLanguages: [Locale.Language]
    public var usesLanguageCorrection: Bool
    public var minimumTextHeightFraction: Float
    public var customWords: [String]

    public init(
        recognitionLevel: RecognizeTextRequest.RecognitionLevel = .accurate,
        automaticallyDetectsLanguage: Bool = true,
        recognitionLanguages: [Locale.Language] = [],
        usesLanguageCorrection: Bool = true,
        minimumTextHeightFraction: Float = 0,
        customWords: [String] = []
    ) {
        self.recognitionLevel = recognitionLevel
        self.automaticallyDetectsLanguage = automaticallyDetectsLanguage
        self.recognitionLanguages = recognitionLanguages
        self.usesLanguageCorrection = usesLanguageCorrection
        self.minimumTextHeightFraction = minimumTextHeightFraction
        self.customWords = customWords
    }
}

public struct OCRTextObservation: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var confidence: Float
    public var normalizedBoundingBox: CGRect

    public init(id: UUID = UUID(), text: String, confidence: Float, normalizedBoundingBox: CGRect) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.normalizedBoundingBox = normalizedBoundingBox
    }
}

public struct OCRResult: Equatable, Sendable {
    public var observations: [OCRTextObservation]
    public var fullText: String

    public init(observations: [OCRTextObservation]) {
        self.observations = observations
        fullText = observations.map(\.text).joined(separator: "\n")
    }
}

public struct VisionOCRProcessor: Sendable {
    public var configuration: OCRConfiguration

    public init(configuration: OCRConfiguration = OCRConfiguration()) {
        self.configuration = configuration
    }

    public func recognizeText(in imageURL: URL, orientation: CGImagePropertyOrientation? = nil) async throws -> OCRResult {
        let handler = ImageRequestHandler(imageURL, orientation: orientation)
        return try await performRecognition(with: handler)
    }

    public func recognizeText(in data: Data, orientation: CGImagePropertyOrientation? = nil) async throws -> OCRResult {
        let handler = ImageRequestHandler(data, orientation: orientation)
        return try await performRecognition(with: handler)
    }

    public func recognizeText(in image: CGImage, orientation: CGImagePropertyOrientation? = nil) async throws -> OCRResult {
        let handler = ImageRequestHandler(image, orientation: orientation)
        return try await performRecognition(with: handler)
    }

    private func performRecognition(with handler: ImageRequestHandler) async throws -> OCRResult {
        var request = RecognizeTextRequest()
        request.recognitionLevel = configuration.recognitionLevel
        request.automaticallyDetectsLanguage = configuration.automaticallyDetectsLanguage
        request.recognitionLanguages = configuration.recognitionLanguages
        request.usesLanguageCorrection = configuration.usesLanguageCorrection
        request.minimumTextHeightFraction = configuration.minimumTextHeightFraction
        request.customWords = configuration.customWords

        let observations = try await handler.perform(request)
        return OCRResult(
            observations: observations.map { observation in
                OCRTextObservation(
                    id: observation.uuid,
                    text: observation.transcript,
                    confidence: observation.confidence,
                    normalizedBoundingBox: Self.boundingBox(for: observation)
                )
            }
        )
    }

    private static func boundingBox(for observation: RecognizedTextObservation) -> CGRect {
        let xs = [
            observation.topLeft.x,
            observation.topRight.x,
            observation.bottomRight.x,
            observation.bottomLeft.x,
        ]
        let ys = [
            observation.topLeft.y,
            observation.topRight.y,
            observation.bottomRight.y,
            observation.bottomLeft.y,
        ]

        guard
            let minX = xs.min(),
            let maxX = xs.max(),
            let minY = ys.min(),
            let maxY = ys.max()
        else {
            return .zero
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
