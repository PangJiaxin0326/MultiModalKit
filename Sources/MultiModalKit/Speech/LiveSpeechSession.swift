@preconcurrency import AVFoundation
import Speech
import Foundation
import OSLog

/// Tunable parameters for a ``LiveSpeechSession``.
public struct LiveSpeechConfiguration: Sendable {
    /// Locale used to select the speech model.
    public var locale: Locale
    /// Sustained silence after speech that ends ``LiveSpeechSession/awaitSilence()``.
    public var silenceDuration: Duration
    /// If the speaker never starts, ``LiveSpeechSession/awaitSilence()`` returns
    /// after this elapses anyway.
    public var noSpeechTimeout: Duration
    /// Normalized input level (`0...1`) at or above which audio counts as speech.
    public var speechThreshold: Double

    public init(
        locale: Locale = .current,
        silenceDuration: Duration = .seconds(1.5),
        noSpeechTimeout: Duration = .seconds(8),
        speechThreshold: Double = 0.12
    ) {
        self.locale = locale
        self.silenceDuration = silenceDuration
        self.noSpeechTimeout = noSpeechTimeout
        self.speechThreshold = speechThreshold
    }
}

/// One live microphone capture + `SpeechAnalyzer` transcription pass.
///
/// A session is single-use: `start()` it, await either ``awaitSilence()`` (to
/// capture an utterance bounded by silence) or ``awaitKeyword(_:)`` (to listen
/// for a command word), then ``finish()`` or ``cancel()`` to tear it down.
/// `transcript` and `audioLevel` update live for UI.
@MainActor
@Observable
public final class LiveSpeechSession {
    /// Combined finalized + in-progress (volatile) transcript, updated live.
    public private(set) var transcript: String = ""
    /// Smoothed input level in `0...1`, suitable for a reactive meter.
    public private(set) var audioLevel: Double = 0

    @ObservationIgnored private let configuration: LiveSpeechConfiguration
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var transcriber: SpeechTranscriber?
    @ObservationIgnored private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var tapBuilder: AsyncStream<AVReadOnlyAudioPCMBuffer>.Continuation?
    @ObservationIgnored private var levelBuilder: AsyncStream<Double>.Continuation?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var pipelineTask: Task<Void, Never>?
    @ObservationIgnored private var levelTask: Task<Void, Never>?
    @ObservationIgnored private var hasInputTap = false

    @ObservationIgnored private var finalizedText = ""
    @ObservationIgnored private var volatileText = ""

    @ObservationIgnored private var silenceWaiter: PendingWaiter?
    @ObservationIgnored private var keywordWaiter: PendingKeywordWaiter?
    @ObservationIgnored private var isTorn = false

    @ObservationIgnored
    private let logger = Logger(subsystem: "com.multimodalkit", category: "LiveSpeech")

    private struct PendingWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct PendingKeywordWaiter {
        let id: UUID
        let keyword: String
        let continuation: CheckedContinuation<Void, Error>
    }

    public init(configuration: LiveSpeechConfiguration = LiveSpeechConfiguration()) {
        self.configuration = configuration
    }

    // MARK: - Lifecycle

    /// Requests permissions, provisions speech assets, and starts the audio
    /// engine + analyzer. Throws before any capture begins on failure.
    public func start() async throws {
        guard analyzer == nil, !engine.isRunning, !isTorn else {
            throw MultiModalKitError.recordingFailed(
                MultiModalKitLocalization.string("Live speech session has already started.")
            )
        }

        try await PermissionCenter.require([.microphone, .speechRecognition])

        guard SpeechTranscriber.isAvailable else {
            throw MultiModalKitError.speechUnavailable
        }
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: configuration.locale
        ) else {
            throw MultiModalKitError.unsupportedSpeechLocale(configuration.locale.identifier)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        try await Self.provisionAssets(for: transcriber)

        do {
            self.transcriber = transcriber

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber]
            ) else {
                throw MultiModalKitError.speechUnavailable
            }

            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.ingest(
                            text: String(result.text.characters),
                            isFinal: result.isFinal
                        )
                    }
                } catch {
                    self?.logger.error("Live transcription stream failed: \(error)")
                }
            }

            let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
            self.inputBuilder = inputBuilder
            try await analyzer.start(inputSequence: inputSequence)

            let (levelSequence, levelBuilder) = AsyncStream<Double>.makeStream()
            self.levelBuilder = levelBuilder

            let (tapSequence, tapBuilder) = AsyncStream<AVReadOnlyAudioPCMBuffer>.makeStream()
            self.tapBuilder = tapBuilder

            let input = engine.inputNode
            let tapFormat = input.outputFormat(forBus: 0)
            try input.installAudioTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
                // Realtime audio thread: only hand the Sendable read-only
                // buffer to the pipeline task; metering and conversion run
                // off this thread.
                tapBuilder.yield(buffer)
            }
            hasInputTap = true

            pipelineTask = Task.detached {
                let converter = AnalyzerInputConverter(analyzerFormat: analyzerFormat)
                for await buffer in tapSequence {
                    levelBuilder.yield(buffer.normalizedPowerLevel())
                    guard let inputs = try? converter.convert(AVAudioPCMBuffer(copying: buffer), at: nil) else {
                        continue
                    }
                    for analyzerInput in inputs {
                        inputBuilder.yield(analyzerInput)
                    }
                }
                if let remaining = try? converter.flush() {
                    for analyzerInput in remaining {
                        inputBuilder.yield(analyzerInput)
                    }
                }
                inputBuilder.finish()
            }

            engine.prepare()
            try engine.start()

            levelTask = Task { [weak self] in
                await self?.consumeLevels(levelSequence)
            }
        } catch {
            cancel()
            throw error
        }
    }

    /// Tears down capture and returns the trimmed final transcript.
    @discardableResult
    public func finish() async -> String {
        guard !isTorn else { return currentTranscript }
        isTorn = true

        if hasInputTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        engine.stop()
        tapBuilder?.finish()
        tapBuilder = nil
        // The pipeline drains the converter and finishes the analyzer input.
        await pipelineTask?.value
        pipelineTask = nil
        inputBuilder = nil
        levelBuilder?.finish()
        levelBuilder = nil

        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        await resultsTask?.value
        levelTask?.cancel()
        failPendingWaiters()
        return currentTranscript
    }

    /// Tears down capture immediately, discarding the transcript.
    public func cancel() {
        guard !isTorn else { return }
        isTorn = true

        if hasInputTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        engine.stop()
        tapBuilder?.finish()
        tapBuilder = nil
        pipelineTask?.cancel()
        pipelineTask = nil
        inputBuilder?.finish()
        inputBuilder = nil
        levelBuilder?.finish()
        levelBuilder = nil
        resultsTask?.cancel()
        levelTask?.cancel()

        let analyzer = analyzer
        Task { await analyzer?.cancelAndFinishNow() }
        failPendingWaiters()
    }

    // MARK: - Awaiting events

    /// Suspends until sustained silence follows detected speech, or the
    /// no-speech timeout elapses. Throws `CancellationError` if torn down.
    public func awaitSilence() async throws {
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled, !isTorn, silenceWaiter == nil else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                silenceWaiter = PendingWaiter(id: waiterID, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in self.cancelSilenceWaiter(id: waiterID) }
        }
    }

    /// Suspends until the live transcript contains `word` (case-insensitive).
    /// Throws `CancellationError` if torn down before the word is heard.
    public func awaitKeyword(_ word: String) async throws {
        let keyword = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled, !isTorn, keywordWaiter == nil else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                keywordWaiter = PendingKeywordWaiter(
                    id: waiterID,
                    keyword: keyword,
                    continuation: continuation
                )
                matchKeyword()
            }
        } onCancel: {
            Task { @MainActor in self.cancelKeywordWaiter(id: waiterID) }
        }
    }

    // MARK: - Transcript

    private var currentTranscript: String {
        (finalizedText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ingest(text: String, isFinal: Bool) {
        if isFinal {
            finalizedText += text
            volatileText = ""
        } else {
            volatileText = text
        }
        transcript = currentTranscript
        matchKeyword()
    }

    private func matchKeyword() {
        guard let waiter = keywordWaiter,
              transcript.range(
                of: waiter.keyword,
                options: [.caseInsensitive, .diacriticInsensitive]
              ) != nil else {
            return
        }

        keywordWaiter = nil
        waiter.continuation.resume()
    }

    // MARK: - Level metering & silence detection

    private func consumeLevels(_ sequence: AsyncStream<Double>) async {
        let clock = ContinuousClock()
        let startedAt = clock.now
        var heardSpeech = false
        var silentSince: ContinuousClock.Instant?

        for await level in sequence {
            audioLevel = audioLevel * 0.7 + level * 0.3
            let now = clock.now

            if level >= configuration.speechThreshold {
                heardSpeech = true
                silentSince = nil
            } else if heardSpeech {
                if let since = silentSince {
                    if now - since >= configuration.silenceDuration { fireSilence() }
                } else {
                    silentSince = now
                }
            } else if now - startedAt >= configuration.noSpeechTimeout {
                fireSilence()
            }
        }
        audioLevel = 0
    }

    private func fireSilence() {
        guard let waiter = silenceWaiter else { return }
        silenceWaiter = nil
        waiter.continuation.resume()
    }

    private func cancelSilenceWaiter(id: UUID) {
        guard let waiter = silenceWaiter, waiter.id == id else { return }
        silenceWaiter = nil
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func cancelKeywordWaiter(id: UUID) {
        guard let waiter = keywordWaiter, waiter.id == id else { return }
        keywordWaiter = nil
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func failPendingWaiters() {
        if let waiter = silenceWaiter {
            silenceWaiter = nil
            waiter.continuation.resume(throwing: CancellationError())
        }
        if let waiter = keywordWaiter {
            keywordWaiter = nil
            waiter.continuation.resume(throwing: CancellationError())
        }
    }

    // MARK: - Asset provisioning

    private static func provisionAssets(for transcriber: SpeechTranscriber) async throws {
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return
        case .supported, .downloading:
            guard let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) else {
                throw MultiModalKitError.speechAssetsUnavailable
            }
            try await request.downloadAndInstall()
        case .unsupported:
            throw MultiModalKitError.speechAssetsUnavailable
        @unknown default:
            throw MultiModalKitError.speechAssetsUnavailable
        }
    }
}

private extension AVReadOnlyAudioPCMBuffer {
    /// RMS amplitude mapped to a perceptual `0...1` range.
    func normalizedPowerLevel() -> Double {
        guard frameLength > 0, case .float(let samples) = channelData(0) else {
            return 0
        }

        var sumOfSquares: Float = 0
        for index in samples.indices {
            let sample = samples[index]
            sumOfSquares += sample * sample
        }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()
        return Double(min(1, max(0, rms * 8))).squareRoot()
    }
}
