import AVFoundation
import Foundation

/// A minimal async wrapper over `AVSpeechSynthesizer`. ``speak(_:)`` suspends
/// until playback finishes, is stopped, or the surrounding task is cancelled.
@MainActor
public final class SpeechSynthesizer: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    /// Resumed by the delegate when the current utterance ends.
    private var utteranceID: ObjectIdentifier?
    private var continuation: CheckedContinuation<Void, Never>?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text`, returning when playback completes. Returns immediately
    /// for empty text. Cancelling the calling task stops playback.
    public func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard !Task.isCancelled else { return }
        let utterance = AVSpeechUtterance(string: trimmed)
        let id = ObjectIdentifier(utterance)

        // Drop any in-flight utterance before starting a new one.
        stop()

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                guard !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                self.utteranceID = id
                self.continuation = continuation
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor in
                guard self.utteranceID == id else { return }
                self.stop()
            }
        }
    }

    /// Stops playback immediately and resumes any pending ``speak(_:)`` caller.
    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        resume()
    }

    private func resume() {
        continuation?.resume()
        continuation = nil
        utteranceID = nil
    }

    private func resume(utteranceID: ObjectIdentifier) {
        guard self.utteranceID == utteranceID else { return }
        resume()
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.resume(utteranceID: id) }
    }

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.resume(utteranceID: id) }
    }
}
