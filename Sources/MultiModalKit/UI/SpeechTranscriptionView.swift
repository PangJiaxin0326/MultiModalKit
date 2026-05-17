import SwiftUI

@MainActor
public struct SpeechTranscriptionView: View {
    @Binding private var transcript: AttributedString
    @Binding private var recordingURL: URL?
    @Binding private var result: SpeechTranscriptionResult?

    @StateObject private var recorder = AudioRecorder()
    @State private var isTranscribing = false
    @State private var errorMessage: String?

    private let audioConfiguration: AudioRecordingConfiguration
    private let speechConfiguration: SpeechTranscriptionConfiguration
    private let service: SpeechTranscriptionService
    private let onResult: (@MainActor (SpeechTranscriptionResult) -> Void)?

    public init(
        transcript: Binding<AttributedString>,
        recordingURL: Binding<URL?> = .constant(nil),
        result: Binding<SpeechTranscriptionResult?> = .constant(nil),
        audioConfiguration: AudioRecordingConfiguration = AudioRecordingConfiguration(),
        speechConfiguration: SpeechTranscriptionConfiguration = SpeechTranscriptionConfiguration(),
        service: SpeechTranscriptionService = SpeechTranscriptionService(),
        onResult: (@MainActor (SpeechTranscriptionResult) -> Void)? = nil
    ) {
        _transcript = transcript
        _recordingURL = recordingURL
        _result = result
        self.audioConfiguration = audioConfiguration
        self.speechConfiguration = speechConfiguration
        self.service = service
        self.onResult = onResult
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                toggleRecording()
            } label: {
                Label(buttonTitle, systemImage: buttonSystemImage)
            }
            .disabled(isTranscribing)

            if isTranscribing {
                ProgressView()
            }

            if !transcript.characters.isEmpty {
                Text(transcript)
                    .textSelection(.enabled)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            if recorder.isRecording {
                _ = recorder.stopRecording()
            }
        }
    }

    private var buttonTitle: LocalizedStringKey {
        if isTranscribing {
            "Transcribing"
        } else if recorder.isRecording {
            "Stop"
        } else {
            "Record"
        }
    }

    private var buttonSystemImage: String {
        if isTranscribing {
            "waveform.badge.magnifyingglass"
        } else if recorder.isRecording {
            "stop.circle.fill"
        } else {
            "mic.circle.fill"
        }
    }

    private func toggleRecording() {
        do {
            if recorder.isRecording {
                guard let url = recorder.stopRecording() else {
                    return
                }
                recordingURL = url
                transcribe(url)
            } else {
                try recorder.startRecording(configuration: audioConfiguration)
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func transcribe(_ url: URL) {
        isTranscribing = true
        Task {
            defer { isTranscribing = false }
            do {
                let transcription = try await service.transcribeAudioFile(at: url, configuration: speechConfiguration)
                transcript = transcription.text
                result = transcription
                onResult?(transcription)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
