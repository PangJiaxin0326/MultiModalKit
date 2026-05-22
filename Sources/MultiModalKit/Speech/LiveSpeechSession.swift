@preconcurrency import AVFoundation
@preconcurrency import Speech
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
    @ObservationIgnored private var levelBuilder: AsyncStream<Double>.Continuation?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var levelTask: Task<Void, Never>?

    @ObservationIgnored private var finalizedText = ""
    @ObservationIgnored private var volatileText = ""

    @ObservationIgnored private var silenceContinuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var keyword: String?
    @ObservationIgnored private var keywordContinuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var isTorn = false

    @ObservationIgnored
    private let logger = Logger(subsystem: "com.multimodalkit", category: "LiveSpeech")

    public init(configuration: LiveSpeechConfiguration = LiveSpeechConfiguration()) {
        self.configuration = configuration
    }

    // MARK: - Lifecycle

    /// Requests permissions, provisions speech assets, and starts the audio
    /// engine + analyzer. Throws before any capture begins on failure.
    public func start() async throws {
        try await PermissionCenter.require(.microphone)
        try await PermissionCenter.require(.speechRecognition)

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

        let input = engine.inputNode
        let tapFormat = input.outputFormat(forBus: 0)
        let converter = BufferConverter()
        input.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
            // Realtime audio thread: no `self`, only Sendable continuations
            // and the converter captured here are touched.
            levelBuilder.yield(buffer.normalizedPowerLevel())
            if let converted = try? converter.convert(buffer, to: analyzerFormat) {
                inputBuilder.yield(AnalyzerInput(buffer: converted))
            }
        }

        engine.prepare()
        try engine.start()

        levelTask = Task { [weak self] in
            await self?.consumeLevels(levelSequence)
        }
    }

    /// Tears down capture and returns the trimmed final transcript.
    @discardableResult
    public func finish() async -> String {
        guard !isTorn else { return currentTranscript }
        isTorn = true

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputBuilder?.finish()
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

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !isTorn, silenceContinuation == nil else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                silenceContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor in self.failPendingWaiters() }
        }
    }

    /// Suspends until the live transcript contains `word` (case-insensitive).
    /// Throws `CancellationError` if torn down before the word is heard.
    public func awaitKeyword(_ word: String) async throws {
        keyword = word.lowercased()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !isTorn, keywordContinuation == nil else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                keywordContinuation = continuation
                matchKeyword()
            }
        } onCancel: {
            Task { @MainActor in self.failPendingWaiters() }
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
        guard let keyword, let continuation = keywordContinuation,
              transcript.lowercased().contains(keyword) else { return }
        keywordContinuation = nil
        continuation.resume()
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
        guard let continuation = silenceContinuation else { return }
        silenceContinuation = nil
        continuation.resume()
    }

    private func failPendingWaiters() {
        if let continuation = silenceContinuation {
            silenceContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
        if let continuation = keywordContinuation {
            keywordContinuation = nil
            continuation.resume(throwing: CancellationError())
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

/// Converts microphone buffers to the analyzer's preferred format. Not
/// `Sendable`; only ever touched from a single audio tap closure.
private final class BufferConverter {
    private var converter: AVAudioConverter?

    func convert(
        _ buffer: AVAudioPCMBuffer,
        to format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        if inputFormat == format { return buffer }

        if converter?.inputFormat != inputFormat || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { throw MultiModalKitError.audioConversionFailed }

        let ratio = format.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw MultiModalKitError.audioConversionFailed
        }

        var conversionError: NSError?
        nonisolated(unsafe) var fedInput = false
        let status = converter.convert(to: output, error: &conversionError) { _, statusPointer in
            if fedInput {
                statusPointer.pointee = .noDataNow
                return nil
            }
            fedInput = true
            statusPointer.pointee = .haveData
            return buffer
        }
        if status == .error { throw MultiModalKitError.audioConversionFailed }
        return output
    }
}

private extension AVAudioPCMBuffer {
    /// RMS amplitude mapped to a perceptual `0...1` range.
    func normalizedPowerLevel() -> Double {
        guard let channelData = floatChannelData else { return 0 }
        let frames = Int(frameLength)
        guard frames > 0 else { return 0 }

        let samples = channelData[0]
        var sumOfSquares: Float = 0
        for index in 0..<frames {
            let sample = samples[index]
            sumOfSquares += sample * sample
        }
        let rms = (sumOfSquares / Float(frames)).squareRoot()
        return Double(min(1, max(0, rms * 8))).squareRoot()
    }
}
