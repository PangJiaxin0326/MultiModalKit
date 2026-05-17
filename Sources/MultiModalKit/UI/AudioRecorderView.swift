import SwiftUI

@MainActor
public struct AudioRecorderView: View {
    @Binding private var recordingURL: URL?

    @StateObject private var recorder = AudioRecorder()
    @State private var errorMessage: String?

    private let configuration: AudioRecordingConfiguration
    private let onFinish: (@MainActor (URL) -> Void)?

    public init(
        recordingURL: Binding<URL?> = .constant(nil),
        configuration: AudioRecordingConfiguration = AudioRecordingConfiguration(),
        onFinish: (@MainActor (URL) -> Void)? = nil
    ) {
        _recordingURL = recordingURL
        self.configuration = configuration
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleRecording()
            } label: {
                Label(
                    recorder.isRecording ? "Stop Recording" : "Record",
                    systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
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

    private func toggleRecording() {
        do {
            if recorder.isRecording {
                guard let url = recorder.stopRecording() else {
                    return
                }
                recordingURL = url
                onFinish?(url)
            } else {
                try recorder.startRecording(configuration: configuration)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
