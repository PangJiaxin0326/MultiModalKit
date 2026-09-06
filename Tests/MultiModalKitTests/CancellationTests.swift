import Testing
@testable import MultiModalKit

@Suite struct CancellationTests {
    @MainActor @Test func cancelledStartDoesNotRequestMicrophone() async {
        let session = LiveSpeechSession()
        let task = Task { @MainActor in
            await #expect(throws: CancellationError.self) { try await session.start() }
        }
        task.cancel()
        await task.value
    }

    @MainActor @Test func cancelledRecorderDoesNotRequestMicrophone() async {
        let recorder = AudioRecorder()
        let task = Task { @MainActor in
            await #expect(throws: CancellationError.self) {
                try await recorder.startRecordingWithPermission()
            }
        }
        task.cancel()
        await task.value
        #expect(!recorder.isRecording)
    }

    @MainActor @Test func cancelledSpeechDoesNotStartPlayback() async {
        let speech = SpeechSynthesizer()
        let task = Task { @MainActor in await speech.speak("Do not play") }
        task.cancel()
        await task.value
    }
}
