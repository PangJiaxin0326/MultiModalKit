import SwiftUI

@MainActor
public struct CameraCaptureView: View {
    @Binding private var capturedImage: CapturedImage?
    @Binding private var capturedImageURL: URL?

    @StateObject private var controller = CameraCaptureController()
    @State private var isCapturing = false
    @State private var errorMessage: String?

    private let onCapture: (@MainActor (CapturedImage) -> Void)?

    public init(
        capturedImage: Binding<CapturedImage?> = .constant(nil),
        capturedImageURL: Binding<URL?> = .constant(nil),
        onCapture: (@MainActor (CapturedImage) -> Void)? = nil
    ) {
        _capturedImage = capturedImage
        _capturedImageURL = capturedImageURL
        self.onCapture = onCapture
    }

    public var body: some View {
        #if os(visionOS)
        ContentUnavailableView {
            Label {
                Text("Camera Capture Unavailable", bundle: .module)
            } icon: {
                Image(systemName: "camera")
            }
        }
        #else
        ZStack(alignment: .bottom) {
            CameraPreview(session: controller.session)
                .overlay {
                    if let errorMessage {
                        ContentUnavailableView {
                            Label {
                                Text("Camera Unavailable", bundle: .module)
                            } icon: {
                                Image(systemName: "camera")
                            }
                        } description: {
                            Text(errorMessage)
                        }
                    }
                }

            Button {
                capture()
            } label: {
                Image(systemName: isCapturing ? "camera.aperture" : "camera.circle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .padding()
            .disabled(isCapturing || errorMessage != nil)
        }
        .task {
            await configureAndStart()
        }
        .onDisappear {
            controller.stop()
        }
        #endif
    }

    private func configureAndStart() async {
        do {
            try await PermissionCenter.require(.camera)
            try controller.configure()
            await controller.start()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func capture() {
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                let image = try await controller.capturePhoto()
                capturedImage = image
                capturedImageURL = image.temporaryFileURL
                onCapture?(image)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
