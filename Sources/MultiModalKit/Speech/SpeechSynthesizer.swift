@preconcurrency import AVFoundation
import Foundation

/// A minimal async wrapper over `AVSpeechSynthesizer`. ``speak(_:)`` suspends
/// until playback finishes, is stopped, or the surrounding task is cancelled.
@MainActor
public final class SpeechSynthesizer: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    /// Resumed by the delegate when the current utterance ends.
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

        // Drop any in-flight utterance before starting a new one.
        stop()

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.continuation = continuation
                synthesizer.speak(AVSpeechUtterance(string: trimmed))
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
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
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.resume() }
    }

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.resume() }
    }
}
