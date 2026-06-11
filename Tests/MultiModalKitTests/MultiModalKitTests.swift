import Testing
import CoreML
@testable import MultiModalKit

@Test func permissionStatusGrantingStates() {
    #expect(MultiModalPermissionStatus.authorized.isGranted)
    #expect(MultiModalPermissionStatus.limited.isGranted)
    #expect(MultiModalPermissionStatus.denied.isGranted == false)
    #expect(MultiModalPermissionStatus.notDetermined.isGranted == false)
    #expect(MultiModalPermissionStatus.notDetermined.canRequestPermission)
    #expect(MultiModalPermissionStatus.denied.shouldOpenSettings)
    #expect(MultiModalPermissionStatus.restricted.shouldOpenSettings == false)
    #expect(MultiModalPermissionStatus.unavailable.shouldOpenSettings == false)
}

@Test func permissionMetadataMatchesSheetPresentation() {
    #expect(MultiModalPermission.camera.displayTitle == "Camera Access")
    #expect(MultiModalPermission.camera.displayName == "camera")
    #expect(MultiModalPermission.camera.symbolName == "camera.fill")
    #expect(MultiModalPermission.camera.privacyUsageDescriptionKey == "NSCameraUsageDescription")
    #expect(MultiModalPermission.photoLibraryReadWrite.displayTitle == "Photo Library Access")
    #expect(MultiModalPermission.photoLibraryReadWrite.symbolName == "photo.stack.fill")
}

@Test func permissionOrderingRemovesDuplicates() {
    let permissions = MultiModalPermission.ordered([
        .photoLibraryReadWrite,
        .camera,
        .speechRecognition,
        .camera,
        .microphone,
    ])

    #expect(permissions == [
        .camera,
        .microphone,
        .speechRecognition,
        .photoLibraryReadWrite,
    ])
}

@Test func permissionStateWrapsPermissionAndStatus() {
    let state = MultiModalPermissionState(
        permission: .photoLibraryReadWrite,
        status: .limited
    )

    #expect(state.id == .photoLibraryReadWrite)
    #expect(state.isGranted)
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
    let output = try MLMultiArray(shape: [1, 6, 3], dataType: .float32)
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

    output[[0, 0, 2] as [NSNumber]] = 51
    output[[0, 1, 2] as [NSNumber]] = 50
    output[[0, 2, 2] as [NSNumber]] = 20
    output[[0, 3, 2] as [NSNumber]] = 10
    output[[0, 4, 2] as [NSNumber]] = 0.1
    output[[0, 5, 2] as [NSNumber]] = 0.7

    let decoded = YOLOv8OutputDecoder.decode(
        multiArray: output,
        classLabels: labels,
        configuration: configuration
    )
    let suppressed = YOLOv8OutputDecoder.nonMaxSuppressed(decoded, iouThreshold: 0.5)

    #expect(decoded.count == 3)
    #expect(suppressed.count == 2)
    #expect(suppressed.first?.label == "tile_a")
    #expect(suppressed.first?.classIndex == 0)
    #expect(suppressed.map(\.label) == ["tile_a", "tile_b"])
}

@Test func yoloV8DecoderClipsBoxesToNormalizedBounds() throws {
    let output = try MLMultiArray(shape: [1, 5, 1], dataType: .float32)
    let labels = ["tile"]
    let configuration = YOLOObjectDetectorConfiguration(
        confidenceThreshold: 0.5,
        inputSize: CGSize(width: 100, height: 100)
    )

    output[[0, 0, 0] as [NSNumber]] = 95
    output[[0, 1, 0] as [NSNumber]] = 5
    output[[0, 2, 0] as [NSNumber]] = 20
    output[[0, 3, 0] as [NSNumber]] = 20
    output[[0, 4, 0] as [NSNumber]] = 0.9

    let decoded = YOLOv8OutputDecoder.decode(
        multiArray: output,
        classLabels: labels,
        configuration: configuration
    )
    let box = try #require(decoded.first?.normalizedBoundingBox)

    #expect(box.minX >= 0)
    #expect(box.minY >= 0)
    #expect(box.maxX <= 1)
    #expect(box.maxY <= 1)
    #expect(abs(box.width - 0.15) < 0.0001)
    #expect(abs(box.height - 0.15) < 0.0001)
}
