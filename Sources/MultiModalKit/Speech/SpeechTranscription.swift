import AVFAudio
import CoreMedia
import Foundation
import Speech

public struct SpeechTranscriptionConfiguration: Sendable {
    public var locale: Locale
    public var preset: SpeechTranscriber.Preset
    public var reserveLocaleAssets: Bool

    public init(
        locale: Locale = .current,
        preset: SpeechTranscriber.Preset = .transcription,
        reserveLocaleAssets: Bool = false
    ) {
        self.locale = locale
        self.preset = preset
        self.reserveLocaleAssets = reserveLocaleAssets
    }
}

public struct SpeechTranscriptSegment: Equatable, Sendable {
    public var text: AttributedString
    public var plainText: String
    public var audioRange: CMTimeRange
    public var finalizationTime: CMTime

    public init(text: AttributedString, audioRange: CMTimeRange, finalizationTime: CMTime) {
        self.text = text
        plainText = String(text.characters)
        self.audioRange = audioRange
        self.finalizationTime = finalizationTime
    }
}

public struct SpeechTranscriptionResult: Equatable, Sendable {
    public var text: AttributedString
    public var plainText: String
    public var segments: [SpeechTranscriptSegment]

    public init(text: AttributedString, segments: [SpeechTranscriptSegment] = []) {
        self.text = text
        plainText = String(text.characters)
        self.segments = segments
    }
}

public struct SpeechTranscriptionService: Sendable {
    public init() {}

    public func transcribeAudioFile(
        at url: URL,
        locale: Locale = .current,
        preset: SpeechTranscriber.Preset = .transcription
    ) async throws -> SpeechTranscriptionResult {
        try await transcribeAudioFile(
            at: url,
            configuration: SpeechTranscriptionConfiguration(locale: locale, preset: preset)
        )
    }

    public func transcribeAudioFile(
        at url: URL,
        configuration: SpeechTranscriptionConfiguration
    ) async throws -> SpeechTranscriptionResult {
        guard SpeechTranscriber.isAvailable else {
            throw MultiModalKitError.speechUnavailable
        }

        let transcriber = try await makeTranscriber(configuration: configuration)
        async let collectedResults = collectResults(from: transcriber)

        let audioFile = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        return try await collectedResults
    }

    public func ensureSpeechAssets(
        locale: Locale = .current,
        preset: SpeechTranscriber.Preset = .transcription,
        reserveLocaleAssets: Bool = false
    ) async throws {
        _ = try await makeTranscriber(
            configuration: SpeechTranscriptionConfiguration(
                locale: locale,
                preset: preset,
                reserveLocaleAssets: reserveLocaleAssets
            )
        )
    }

    private func makeTranscriber(configuration: SpeechTranscriptionConfiguration) async throws -> SpeechTranscriber {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: configuration.locale) else {
            throw MultiModalKitError.unsupportedSpeechLocale(configuration.locale.identifier)
        }

        if configuration.reserveLocaleAssets {
            try await AssetInventory.reserve(locale: supportedLocale)
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: configuration.preset)
        try await ensureAssets(for: transcriber)
        return transcriber
    }

    private func ensureAssets(for transcriber: SpeechTranscriber) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        switch status {
        case .installed:
            return
        case .supported, .downloading:
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                throw MultiModalKitError.speechAssetsUnavailable
            }
            try await request.downloadAndInstall()
        case .unsupported:
            throw MultiModalKitError.speechAssetsUnavailable
        @unknown default:
            throw MultiModalKitError.speechAssetsUnavailable
        }
    }

    private func collectResults(from transcriber: SpeechTranscriber) async throws -> SpeechTranscriptionResult {
        var transcript = AttributedString()
        var segments: [SpeechTranscriptSegment] = []

        for try await result in transcriber.results {
            guard result.isFinal else {
                continue
            }

            transcript += result.text
            segments.append(
                SpeechTranscriptSegment(
                    text: result.text,
                    audioRange: result.range,
                    finalizationTime: result.resultsFinalizationTime
                )
            )
        }

        return SpeechTranscriptionResult(text: transcript, segments: segments)
    }
}
