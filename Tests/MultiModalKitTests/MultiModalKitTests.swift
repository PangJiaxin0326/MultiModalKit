import Testing
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
