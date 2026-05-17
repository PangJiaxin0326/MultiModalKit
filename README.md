# MultiModalKit

MultiModalKit bundles common voice, vision, speech, camera, microphone, and photo-library workflows behind one Swift package for iOS, macOS, and visionOS 26.5 or later.

## Capabilities

- Check and request camera, microphone, speech-recognition, and photo-library permissions with `PermissionCenter`.
- Transcribe recorded audio with `SpeechTranscriptionService`, built on the iOS/macOS/visionOS 26 SpeechAnalyzer and SpeechTranscriber APIs.
- Recognize text in images, image data, camera captures, and file URLs with `VisionOCRProcessor`.
- Capture still images using AVFoundation with `CameraCaptureView`.
- Record audio to temporary files with `AudioRecorder` and `AudioRecorderView`.
- Pick images from the photo library with `PhotoPickerButton`.
- Use built-in SwiftUI views that either mutate external bindings or call result handlers.

On visionOS, the SDK currently marks AVFoundation photo capture and preview-layer APIs unavailable. MultiModalKit still builds for visionOS and returns a graceful unavailable state for camera capture UI and APIs there.

## Host App Privacy Keys

The host app remains responsible for adding the relevant usage descriptions to its Info.plist:

- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`
- `NSPhotoLibraryUsageDescription`
- `NSPhotoLibraryAddUsageDescription` when requesting add-only photo access

## Quick Examples

```swift
import MultiModalKit
import SwiftUI

struct CaptureScreen: View {
    @State private var imageURL: URL?
    @State private var ocrResult: OCRResult?

    var body: some View {
        CameraOCRView(capturedImageURL: $imageURL, ocrResult: $ocrResult)
    }
}
```

```swift
let status = PermissionCenter.status(for: .microphone)
let granted = await PermissionCenter.request(.microphone).isGranted
```

```swift
let transcription = try await SpeechTranscriptionService()
    .transcribeAudioFile(at: audioURL, locale: .current)
```
