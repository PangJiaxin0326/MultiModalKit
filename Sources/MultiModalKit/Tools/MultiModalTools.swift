import AIToolKit
import Foundation

/// Registers MultiModalKit's capabilities as AIToolKit ``Tool``s.
public enum MultiModalTools {
    /// Registers every MultiModalKit tool into `registry`.
    ///
    /// Stateful tools get a dedicated capture object: ``RecordAudioTool`` an
    /// ``AudioRecorder`` and ``CapturePhotoTool`` a ``CameraCaptureController``,
    /// so the registry can drive each across multiple invocations.
    @MainActor
    public static func registerAll(in registry: ToolRegistry) async {
        await registry.register(RecognizeTextTool())
        await registry.register(SpeakTextTool())
        await registry.register(TranscribeAudioFileTool())
        await registry.register(TranscribeSpeechTool())
        await registry.register(ImportPhotoTool())
        await registry.register(RecordAudioTool(recorder: AudioRecorder()))
        await registry.register(CapturePhotoTool(controller: CameraCaptureController()))
    }
}
