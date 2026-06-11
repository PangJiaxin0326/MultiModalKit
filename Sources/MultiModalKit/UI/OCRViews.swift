import SwiftUI

@MainActor
public struct PhotoOCRPickerView: View {
    @Binding private var photo: PickedPhoto?
    @Binding private var ocrResult: OCRResult?

    @State private var errorMessage: String?
    @State private var recognitionTask: Task<Void, Never>?
    @State private var recognitionTaskID: UUID?

    private let processor: VisionOCRProcessor
    private let title: String
    private let systemImage: String
    private let onResult: (@MainActor (OCRResult) -> Void)?

    public init(
        title: String = "Choose Image",
        systemImage: String = "text.viewfinder",
        photo: Binding<PickedPhoto?> = .constant(nil),
        ocrResult: Binding<OCRResult?>,
        processor: VisionOCRProcessor = VisionOCRProcessor(),
        onResult: (@MainActor (OCRResult) -> Void)? = nil
    ) {
        _photo = photo
        _ocrResult = ocrResult
        self.processor = processor
        self.title = title
        self.systemImage = systemImage
        self.onResult = onResult
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotoPickerButton(title: title, systemImage: systemImage, photo: $photo) { pickedPhoto in
                recognizeText(in: pickedPhoto)
            }

            if let fullText = ocrResult?.fullText, !fullText.isEmpty {
                Text(fullText)
                    .textSelection(.enabled)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionTaskID = nil
        }
    }

    private func recognizeText(in photo: PickedPhoto) {
        recognitionTask?.cancel()
        let taskID = UUID()
        recognitionTaskID = taskID
        recognitionTask = Task {
            defer {
                if recognitionTaskID == taskID {
                    recognitionTask = nil
                    recognitionTaskID = nil
                }
            }
            do {
                let result = try await processor.recognizeText(in: photo.data)
                guard !Task.isCancelled, recognitionTaskID == taskID else { return }
                ocrResult = result
                onResult?(result)
                errorMessage = nil
            } catch {
                guard !Task.isCancelled, recognitionTaskID == taskID else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

@MainActor
public struct CameraOCRView: View {
    @Binding private var capturedImageURL: URL?
    @Binding private var ocrResult: OCRResult?

    @State private var capturedImage: CapturedImage?
    @State private var errorMessage: String?
    @State private var recognitionTask: Task<Void, Never>?
    @State private var recognitionTaskID: UUID?

    private let processor: VisionOCRProcessor
    private let onCapture: (@MainActor (CapturedImage) -> Void)?
    private let onResult: (@MainActor (OCRResult) -> Void)?

    public init(
        capturedImageURL: Binding<URL?> = .constant(nil),
        ocrResult: Binding<OCRResult?>,
        processor: VisionOCRProcessor = VisionOCRProcessor(),
        onCapture: (@MainActor (CapturedImage) -> Void)? = nil,
        onResult: (@MainActor (OCRResult) -> Void)? = nil
    ) {
        _capturedImageURL = capturedImageURL
        _ocrResult = ocrResult
        self.processor = processor
        self.onCapture = onCapture
        self.onResult = onResult
    }

    public init(
        capturedImageURL: Binding<URL?> = .constant(nil),
        ocrResult: Binding<OCRResult?>,
        processor: VisionOCRProcessor = VisionOCRProcessor(),
        onResult: @escaping @MainActor (OCRResult) -> Void
    ) {
        self.init(
            capturedImageURL: capturedImageURL,
            ocrResult: ocrResult,
            processor: processor,
            onCapture: nil,
            onResult: onResult
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CameraCaptureView(capturedImage: $capturedImage, capturedImageURL: $capturedImageURL) { image in
                onCapture?(image)
                recognizeText(in: image)
            }

            if let fullText = ocrResult?.fullText, !fullText.isEmpty {
                Text(fullText)
                    .textSelection(.enabled)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionTaskID = nil
        }
    }

    private func recognizeText(in image: CapturedImage) {
        recognitionTask?.cancel()
        let taskID = UUID()
        recognitionTaskID = taskID
        recognitionTask = Task {
            defer {
                if recognitionTaskID == taskID {
                    recognitionTask = nil
                    recognitionTaskID = nil
                }
            }
            do {
                let result = try await processor.recognizeText(in: image.data)
                guard !Task.isCancelled, recognitionTaskID == taskID else { return }
                ocrResult = result
                onResult?(result)
                errorMessage = nil
            } catch {
                guard !Task.isCancelled, recognitionTaskID == taskID else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
