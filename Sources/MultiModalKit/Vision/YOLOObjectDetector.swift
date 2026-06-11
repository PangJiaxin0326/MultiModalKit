import CoreGraphics
import CoreML
import Foundation
import ImageIO
import Vision

public struct YOLOObjectDetectorConfiguration: Equatable, Sendable {
    public var confidenceThreshold: Float
    public var iouThreshold: Float
    public var inputSize: CGSize
    public var imageCropAndScaleOption: VNImageCropAndScaleOption

    public init(
        confidenceThreshold: Float = 0.54,
        iouThreshold: Float = 0.85,
        inputSize: CGSize = CGSize(width: 640, height: 640),
        imageCropAndScaleOption: VNImageCropAndScaleOption = .scaleFill
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.iouThreshold = iouThreshold
        self.inputSize = inputSize
        self.imageCropAndScaleOption = imageCropAndScaleOption
    }
}

public struct DetectedObject: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var confidence: Float
    public var normalizedBoundingBox: CGRect
    public var classIndex: Int?

    public init(
        id: UUID = UUID(),
        label: String,
        confidence: Float,
        normalizedBoundingBox: CGRect,
        classIndex: Int? = nil
    ) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.normalizedBoundingBox = normalizedBoundingBox
        self.classIndex = classIndex
    }
}

public struct ObjectDetectionResult: Equatable, Sendable {
    public var detections: [DetectedObject]
    public var imageSize: CGSize?

    public init(detections: [DetectedObject], imageSize: CGSize? = nil) {
        self.detections = detections
        self.imageSize = imageSize
    }
}

public final class YOLOObjectDetector {
    private let visionModel: VNCoreMLModel
    private let classLabels: [String]
    private let configuration: YOLOObjectDetectorConfiguration

    public convenience init(
        modelURL: URL,
        classLabels: [String],
        configuration: YOLOObjectDetectorConfiguration = YOLOObjectDetectorConfiguration()
    ) throws {
        let compiledURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            compiledURL = modelURL
        } else {
            do {
                compiledURL = try MLModel.compileModel(at: modelURL)
            } catch {
                throw MultiModalKitError.modelLoadFailed(error.localizedDescription)
            }
        }

        do {
            let model = try MLModel(contentsOf: compiledURL)
            try self.init(model: model, classLabels: classLabels, configuration: configuration)
        } catch let error as MultiModalKitError {
            throw error
        } catch {
            throw MultiModalKitError.modelLoadFailed(error.localizedDescription)
        }
    }

    public init(
        model: MLModel,
        classLabels: [String],
        configuration: YOLOObjectDetectorConfiguration = YOLOObjectDetectorConfiguration()
    ) throws {
        do {
            visionModel = try VNCoreMLModel(for: model)
            self.classLabels = classLabels
            self.configuration = configuration
        } catch {
            throw MultiModalKitError.modelLoadFailed(error.localizedDescription)
        }
    }

    public func detectObjects(
        in imageURL: URL,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> ObjectDetectionResult {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = configuration.imageCropAndScaleOption

        let handler = VNImageRequestHandler(url: imageURL, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            throw MultiModalKitError.objectDetectionFailed(error.localizedDescription)
        }

        return try result(from: request.results)
    }

    public func detectObjects(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> ObjectDetectionResult {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = configuration.imageCropAndScaleOption

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            throw MultiModalKitError.objectDetectionFailed(error.localizedDescription)
        }

        return try result(from: request.results, imageSize: CGSize(width: cgImage.width, height: cgImage.height))
    }

    private func result(from observations: [VNObservation]?, imageSize: CGSize? = nil) throws -> ObjectDetectionResult {
        guard let observations else {
            return ObjectDetectionResult(detections: [], imageSize: imageSize)
        }

        let recognizedObjects = observations.compactMap { $0 as? VNRecognizedObjectObservation }
        if !recognizedObjects.isEmpty {
            let detections = recognizedObjects.compactMap {
                Self.detectedObject(
                    from: $0,
                    minimumConfidence: configuration.confidenceThreshold
                )
            }
            return ObjectDetectionResult(
                detections: YOLOv8OutputDecoder.nonMaxSuppressed(
                    detections,
                    iouThreshold: configuration.iouThreshold
                ),
                imageSize: imageSize
            )
        }

        let rawDetections = observations.compactMap { observation -> [DetectedObject]? in
            guard
                let feature = observation as? VNCoreMLFeatureValueObservation,
                let multiArray = feature.featureValue.multiArrayValue
            else {
                return nil
            }
            return YOLOv8OutputDecoder.decode(
                multiArray: multiArray,
                classLabels: classLabels,
                configuration: configuration
            )
        }
        .flatMap(\.self)

        return ObjectDetectionResult(
            detections: YOLOv8OutputDecoder.nonMaxSuppressed(
                rawDetections,
                iouThreshold: configuration.iouThreshold
            ),
            imageSize: imageSize
        )
    }

    private static func detectedObject(
        from observation: VNRecognizedObjectObservation,
        minimumConfidence: Float
    ) -> DetectedObject? {
        guard let label = observation.labels.first else { return nil }
        guard label.confidence >= minimumConfidence else { return nil }
        return DetectedObject(
            label: label.identifier,
            confidence: label.confidence,
            normalizedBoundingBox: observation.boundingBox
        )
    }
}

enum YOLOv8OutputDecoder {
    static func decode(
        multiArray: MLMultiArray,
        classLabels: [String],
        configuration: YOLOObjectDetectorConfiguration
    ) -> [DetectedObject] {
        let shape = multiArray.shape.map(\.intValue)
        let classCount = classLabels.count
        guard let layout = YOLOv8TensorLayout(shape: shape, classCount: classCount) else {
            return []
        }

        let reader = MLMultiArrayValueReader(multiArray)
        var detections: [DetectedObject] = []
        detections.reserveCapacity(min(layout.candidateCount, 256))

        for candidateIndex in 0..<layout.candidateCount {
            var bestClassIndex = 0
            var bestConfidence: Float = 0

            for classOffset in 0..<classCount {
                let confidence = layout.value(
                    in: reader,
                    candidateIndex: candidateIndex,
                    attributeIndex: 4 + classOffset
                )
                if confidence > bestConfidence {
                    bestConfidence = confidence
                    bestClassIndex = classOffset
                }
            }

            guard bestConfidence >= configuration.confidenceThreshold else {
                continue
            }

            let centerX = layout.value(in: reader, candidateIndex: candidateIndex, attributeIndex: 0)
            let centerY = layout.value(in: reader, candidateIndex: candidateIndex, attributeIndex: 1)
            let width = layout.value(in: reader, candidateIndex: candidateIndex, attributeIndex: 2)
            let height = layout.value(in: reader, candidateIndex: candidateIndex, attributeIndex: 3)

            let normalizedRect = normalizedBoundingBox(
                centerX: centerX,
                centerY: centerY,
                width: width,
                height: height,
                inputSize: configuration.inputSize
            )

            guard !normalizedRect.isNull, normalizedRect.width > 0, normalizedRect.height > 0 else {
                continue
            }

            detections.append(DetectedObject(
                label: classLabels[safe: bestClassIndex] ?? "\(bestClassIndex)",
                confidence: bestConfidence,
                normalizedBoundingBox: normalizedRect,
                classIndex: bestClassIndex
            ))
        }

        return detections
    }

    static func nonMaxSuppressed(_ detections: [DetectedObject], iouThreshold: Float) -> [DetectedObject] {
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var isSuppressed = Array(repeating: false, count: sorted.count)
        var selected: [DetectedObject] = []
        selected.reserveCapacity(sorted.count)

        for index in sorted.indices where !isSuppressed[index] {
            let best = sorted[index]
            selected.append(best)

            let nextIndex = sorted.index(after: index)
            guard nextIndex < sorted.endIndex else { continue }

            for candidateIndex in nextIndex..<sorted.endIndex where !isSuppressed[candidateIndex] {
                let candidate = sorted[candidateIndex]
                guard shouldCompareForSuppression(best, candidate) else {
                    continue
                }

                if intersectionOverUnion(best.normalizedBoundingBox, candidate.normalizedBoundingBox) >= CGFloat(iouThreshold) {
                    isSuppressed[candidateIndex] = true
                }
            }
        }

        return selected
    }

    private static func normalizedBoundingBox(
        centerX: Float,
        centerY: Float,
        width: Float,
        height: Float,
        inputSize: CGSize
    ) -> CGRect {
        guard inputSize.width > 0, inputSize.height > 0 else {
            return .null
        }

        let inputWidth = Float(inputSize.width)
        let inputHeight = Float(inputSize.height)

        let normalizedWidth = width / inputWidth
        let normalizedHeight = height / inputHeight
        guard normalizedWidth > 0, normalizedHeight > 0 else {
            return .null
        }

        let minX = CGFloat((centerX - width / 2) / inputWidth).clamped(to: 0...1)
        let maxX = CGFloat((centerX + width / 2) / inputWidth).clamped(to: 0...1)
        let minY = CGFloat(1 - (centerY + height / 2) / inputHeight).clamped(to: 0...1)
        let maxY = CGFloat(1 - (centerY - height / 2) / inputHeight).clamped(to: 0...1)

        guard maxX > minX, maxY > minY else {
            return .null
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private static func shouldCompareForSuppression(_ lhs: DetectedObject, _ rhs: DetectedObject) -> Bool {
        if let lhsClass = lhs.classIndex, let rhsClass = rhs.classIndex {
            return lhsClass == rhsClass
        }
        return lhs.label == rhs.label
    }
}

private struct MLMultiArrayValueReader {
    let multiArray: MLMultiArray
    let dataPointer: UnsafeMutableRawPointer
    let dataType: MLMultiArrayDataType
    let strides: [Int]

    init(_ multiArray: MLMultiArray) {
        self.multiArray = multiArray
        dataPointer = multiArray.dataPointer
        dataType = multiArray.dataType
        strides = multiArray.strides.map(\.intValue)
    }

    func value(at offset: Int) -> Float {
        switch dataType {
        case .float16:
            Float(dataPointer.assumingMemoryBound(to: Float16.self)[offset])
        case .float32:
            dataPointer.assumingMemoryBound(to: Float.self)[offset]
        case .double:
            Float(dataPointer.assumingMemoryBound(to: Double.self)[offset])
        case .int8:
            Float(dataPointer.assumingMemoryBound(to: Int8.self)[offset])
        case .int32:
            Float(dataPointer.assumingMemoryBound(to: Int32.self)[offset])
        @unknown default:
            0
        }
    }
}

private struct YOLOv8TensorLayout {
    let shape: [Int]
    let candidateCount: Int
    let candidateDimension: Int
    let attributeDimension: Int

    init?(shape: [Int], classCount: Int) {
        let expectedAttributes = classCount + 4

        switch shape.count {
        case 2:
            if shape[0] == expectedAttributes {
                self.init(
                    shape: shape,
                    candidateCount: shape[1],
                    candidateDimension: 1,
                    attributeDimension: 0
                )
            } else if shape[1] == expectedAttributes {
                self.init(
                    shape: shape,
                    candidateCount: shape[0],
                    candidateDimension: 0,
                    attributeDimension: 1
                )
            } else {
                return nil
            }
        case 3:
            if shape[1] == expectedAttributes {
                self.init(
                    shape: shape,
                    candidateCount: shape[2],
                    candidateDimension: 2,
                    attributeDimension: 1
                )
            } else if shape[2] == expectedAttributes {
                self.init(
                    shape: shape,
                    candidateCount: shape[1],
                    candidateDimension: 1,
                    attributeDimension: 2
                )
            } else {
                return nil
            }
        default:
            return nil
        }
    }

    private init(
        shape: [Int],
        candidateCount: Int,
        candidateDimension: Int,
        attributeDimension: Int
    ) {
        self.shape = shape
        self.candidateCount = candidateCount
        self.candidateDimension = candidateDimension
        self.attributeDimension = attributeDimension
    }

    func value(
        in reader: MLMultiArrayValueReader,
        candidateIndex: Int,
        attributeIndex: Int
    ) -> Float {
        guard let offset = offset(
            candidateIndex: candidateIndex,
            attributeIndex: attributeIndex,
            strides: reader.strides
        ) else {
            return 0
        }

        return reader.value(at: offset)
    }

    private func offset(candidateIndex: Int, attributeIndex: Int, strides: [Int]) -> Int? {
        guard strides.count == shape.count else {
            return nil
        }

        let indexes: [Int]
        switch shape.count {
        case 2:
            indexes = candidateDimension == 0
                ? [candidateIndex, attributeIndex]
                : [attributeIndex, candidateIndex]
        case 3:
            var values = [0, 0, 0]
            values[candidateDimension] = candidateIndex
            values[attributeDimension] = attributeIndex
            indexes = values
        default:
            return nil
        }

        return zip(indexes, strides).reduce(0) { offset, valueAndStride in
            offset + valueAndStride.0 * valueAndStride.1
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
