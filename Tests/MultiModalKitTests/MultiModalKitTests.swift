import Testing
import CoreML
@testable import MultiModalKit

@Test func permissionStatusGrantingStates() {
    #expect(MultiModalPermissionStatus.authorized.isGranted)
    #expect(MultiModalPermissionStatus.limited.isGranted)
    #expect(!MultiModalPermissionStatus.denied.isGranted)
    #expect(!MultiModalPermissionStatus.notDetermined.isGranted)
}

@Test func ocrResultBuildsFullText() {
    let result = OCRResult(
        observations: [
            OCRTextObservation(text: "Hello", confidence: 0.9, normalizedBoundingBox: .zero),
            OCRTextObservation(text: "World", confidence: 0.8, normalizedBoundingBox: .zero),
        ]
    )

    #expect(result.fullText == "Hello\nWorld")
}

@Test func audioRecordingConfigurationDefaultsToM4A() {
    let configuration = AudioRecordingConfiguration()

    #expect(configuration.format == .m4a)
    #expect(configuration.sampleRate == 44_100)
    #expect(configuration.channelCount == 1)
}

@Test func yoloV8DecoderReadsRawTensorOutputAndSuppressesOverlap() throws {
    let output = try MLMultiArray(shape: [1, 6, 2], dataType: .float32)
    let labels = ["tile_a", "tile_b"]
    let configuration = YOLOObjectDetectorConfiguration(
        confidenceThreshold: 0.5,
        iouThreshold: 0.5,
        inputSize: CGSize(width: 100, height: 100)
    )

    output[[0, 0, 0] as [NSNumber]] = 50
    output[[0, 1, 0] as [NSNumber]] = 50
    output[[0, 2, 0] as [NSNumber]] = 20
    output[[0, 3, 0] as [NSNumber]] = 10
    output[[0, 4, 0] as [NSNumber]] = 0.9
    output[[0, 5, 0] as [NSNumber]] = 0.1

    output[[0, 0, 1] as [NSNumber]] = 51
    output[[0, 1, 1] as [NSNumber]] = 50
    output[[0, 2, 1] as [NSNumber]] = 20
    output[[0, 3, 1] as [NSNumber]] = 10
    output[[0, 4, 1] as [NSNumber]] = 0.8
    output[[0, 5, 1] as [NSNumber]] = 0.2

    let decoded = YOLOv8OutputDecoder.decode(
        multiArray: output,
        classLabels: labels,
        configuration: configuration
    )
    let suppressed = YOLOv8OutputDecoder.nonMaxSuppressed(decoded, iouThreshold: 0.5)

    #expect(decoded.count == 2)
    #expect(suppressed.count == 1)
    #expect(suppressed.first?.label == "tile_a")
    #expect(suppressed.first?.classIndex == 0)
}
