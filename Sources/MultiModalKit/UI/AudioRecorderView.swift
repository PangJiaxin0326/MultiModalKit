import SwiftUI

@MainActor
public struct AudioRecorderView: View {
    @Binding private var recordingURL: URL?

    @StateObject private var recorder = AudioRecorder()
    @State private var errorMessage: String?
    @State private var isProcessing = false

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
                Task {
                    await toggleRecording()
                }
            } label: {
                Label(
                    recorder.isRecording ? "Stop Recording" : "Record",
                    systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
            }
            .disabled(isProcessing)

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

    private func toggleRecording() async {
        guard !isProcessing else {
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            if recorder.isRecording {
                guard let url = recorder.stopRecording() else {
                    return
                }
                recordingURL = url
                onFinish?(url)
            } else {
                try await recorder.startRecordingWithPermission(configuration: configuration)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
