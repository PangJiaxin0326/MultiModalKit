import AIToolKit
import Foundation

/// MultiModalKit's capabilities as AIToolKit ``Tool``s.
public enum MultiModalTools {
    /// Every MultiModalKit tool, in the `[any Tool]` currency a
    /// `LanguageModelSession` (or a `WorkflowTool`) takes.
    ///
    /// Stateful tools get a dedicated capture object: ``RecordAudioTool`` an
    /// ``AudioRecorder`` and ``CapturePhotoTool`` a ``CameraCaptureController``,
    /// so each tool instance can be driven across multiple invocations.
    @MainActor
    public static func all() -> [any Tool] {
        [
            RecognizeTextTool(),
            SpeakTextTool(),
            TranscribeAudioFileTool(),
            TranscribeSpeechTool(),
            ImportPhotoTool(),
            RecordAudioTool(recorder: AudioRecorder()),
            CapturePhotoTool(controller: CameraCaptureController()),
        ]
    }
}
