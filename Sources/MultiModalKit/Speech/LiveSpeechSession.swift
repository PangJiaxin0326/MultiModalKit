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
///
/// The efficient live microphone path (`AVReadOnlyAudioPCMBuffer`, `installAudioTap`,
/// `AnalyzerInputConverter`) is iOS 27 API. The `SpeechAnalyzer`/`SpeechTranscriber`
/// engine and `AnalyzerInput` are iOS 26, so on iOS 26 the session falls back to a
/// classic `installTap` + `AVAudioConverter` capture (gated with `if #available`) and
/// the feature works there too — no type-level `@available` gate required.
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
    @ObservationIgnored private var tapBuilder: AsyncStream<AVAudioPCMBuffer>.Continuation?
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
    @ObservationIgnored private var isStarting = false

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
        guard analyzer == nil, !engine.isRunning, !isTorn, !isStarting else {
            throw MultiModalKitError.recordingFailed(
                MultiModalKitLocalization.string("Live speech session has already started.")
            )
        }

        isStarting = true
        defer { isStarting = false }
        try Task.checkCancellation()
        try await PermissionCenter.require([.microphone, .speechRecognition])
        try checkStartIsActive()

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
        try checkStartIsActive()

        do {
            self.transcriber = transcriber

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber]
            ) else {
                throw MultiModalKitError.speechUnavailable
            }

            try checkStartIsActive()
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
            try checkStartIsActive()

            let (levelSequence, levelBuilder) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
            self.levelBuilder = levelBuilder

            let (tapSequence, tapBuilder) = AsyncStream<AVAudioPCMBuffer>.makeStream()
            self.tapBuilder = tapBuilder

            let input = engine.inputNode
            let tapFormat = input.outputFormat(forBus: 0)
            // iOS 27 hands the tap a Sendable read-only buffer; iOS 26 uses the classic
            // mutable-buffer tap. Either way we forward an `AVAudioPCMBuffer` to the
            // off-thread pipeline, so everything downstream is version-agnostic.
            if #available(iOS 27, macOS 27, visionOS 27, *) {
                try input.installAudioTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
                    tapBuilder.yield(AVAudioPCMBuffer(copying: buffer))
                }
            } else {
                input.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
                    // The engine reuses the tap buffer; transfer an owned copy.
                    if let copy = buffer.copy() as? AVAudioPCMBuffer {
                        tapBuilder.yield(copy)
                    }
                }
            }
            hasInputTap = true

            pipelineTask = Task.detached {
                let converter = AnalyzerInputPipeline(tapFormat: tapFormat, analyzerFormat: analyzerFormat)
                for await buffer in tapSequence {
                    levelBuilder.yield(buffer.normalizedPowerLevel())
                    for analyzerInput in converter.convert(buffer) {
                        inputBuilder.yield(analyzerInput)
                    }
                }
                for analyzerInput in converter.flush() {
                    inputBuilder.yield(analyzerInput)
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

    private func checkStartIsActive() throws {
        try Task.checkCancellation()
        if isTorn { throw CancellationError() }
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

private extension AVAudioPCMBuffer {
    /// RMS amplitude mapped to a perceptual `0...1` range.
    func normalizedPowerLevel() -> Double {
        guard frameLength > 0, let channel = floatChannelData?[0] else {
            return 0
        }

        let count = Int(frameLength)
        var sumOfSquares: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sumOfSquares += sample * sample
        }
        let rms = (sumOfSquares / Float(count)).squareRoot()
        return Double(min(1, max(0, rms * 8))).squareRoot()
    }
}

/// Turns captured `AVAudioPCMBuffer`s into `AnalyzerInput`s for `SpeechAnalyzer`.
///
/// iOS 27 uses the framework's `AnalyzerInputConverter` (handles format conversion and
/// buffering). iOS 26 has the analyzer + `AnalyzerInput(buffer:)` but not that converter,
/// so it falls back to an `AVAudioConverter` into the analyzer's format. Created and used
/// entirely inside one detached pipeline task, so it needs no cross-actor synchronisation.
private final class AnalyzerInputPipeline {
    private let analyzerFormat: AVAudioFormat
    /// `AnalyzerInputConverter` on iOS 27 (stored type-erased so this iOS-26-available type
    /// has no stored property of an iOS-27 type); `nil` on the iOS 26 fallback path.
    private let modern: Any?
    private let legacy: AVAudioConverter?

    init(tapFormat: AVAudioFormat, analyzerFormat: AVAudioFormat) {
        self.analyzerFormat = analyzerFormat
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            self.modern = AnalyzerInputConverter(analyzerFormat: analyzerFormat)
            self.legacy = nil
        } else {
            self.modern = nil
            self.legacy = tapFormat == analyzerFormat
                ? nil
                : AVAudioConverter(from: tapFormat, to: analyzerFormat)
        }
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [AnalyzerInput] {
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            guard let converter = modern as? AnalyzerInputConverter else { return [] }
            return (try? converter.convert(buffer, at: nil)) ?? []
        }
        return legacyConvert(buffer)
    }

    func flush() -> [AnalyzerInput] {
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            guard let converter = modern as? AnalyzerInputConverter else { return [] }
            return (try? converter.flush()) ?? []
        }
        return []   // the iOS 26 path converts buffer-by-buffer, so nothing is buffered
    }

    /// iOS 26: resample into the analyzer's format (when it differs) and wrap as input.
    private func legacyConvert(_ buffer: AVAudioPCMBuffer) -> [AnalyzerInput] {
        guard let converter = legacy else {
            // Already the analyzer's format — feed it straight through.
            return [AnalyzerInput(buffer: buffer)]
        }
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else {
            return []
        }
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return [] }
        return [AnalyzerInput(buffer: output)]
    }
}
