@preconcurrency import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

#if os(visionOS)
@MainActor
public final class CameraCaptureController: NSObject, ObservableObject {
    @Published public private(set) var isConfigured = false
    @Published public private(set) var isRunning = false
    @Published public private(set) var lastError: Error?

    public override init() {
        super.init()
    }

    public func configure() throws {
        throw MultiModalKitError.unavailable(MultiModalKitLocalization.string("Camera photo capture"))
    }

    public func start() {
        isRunning = false
    }

    public func start() async {
        isRunning = false
    }

    public func stop() {
        isRunning = false
    }

    public func stop() async {
        isRunning = false
    }

    public func capturePhoto(to url: URL? = nil) async throws -> CapturedImage {
        throw MultiModalKitError.unavailable(MultiModalKitLocalization.string("Camera photo capture"))
    }
}
#else
@MainActor
public final class CameraCaptureController: NSObject, ObservableObject {
    @Published public private(set) var isConfigured = false
    @Published public private(set) var isRunning = false
    @Published public private(set) var lastError: Error?

    public let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "MultiModalKit.CameraCaptureController.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var photoDelegates: [UUID: PhotoCaptureDelegate] = [:]

    public override init() {
        super.init()
    }

    public func configure() throws {
        guard !isConfigured else {
            return
        }

        let session = session
        let photoOutput = photoOutput

        do {
            try sessionQueue.sync {
                session.beginConfiguration()
                session.sessionPreset = .photo
                defer { session.commitConfiguration() }

                guard let camera = AVCaptureDevice.default(for: .video) else {
                    throw MultiModalKitError.cameraNotFound
                }

                let input = try AVCaptureDeviceInput(device: camera)
                guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
                    throw MultiModalKitError.captureFailed(
                        MultiModalKitLocalization.string(
                            "The camera input or photo output could not be added."
                        )
                    )
                }

                session.addInput(input)
                session.addOutput(photoOutput)
            }
            isConfigured = true
            lastError = nil
        } catch {
            lastError = error
            throw error
        }
    }

    public func start() {
        guard isConfigured else {
            isRunning = false
            return
        }

        Task {
            await startRunning()
        }
    }

    public func start() async {
        guard isConfigured else {
            isRunning = false
            return
        }

        await startRunning()
    }

    public func stop() {
        Task {
            await stopRunning()
        }
    }

    public func stop() async {
        await stopRunning()
    }

    private func startRunning() async {
        let session = session
        let sessionQueue = sessionQueue

        let running = await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume(returning: session.isRunning)
            }
        }

        isRunning = running
    }

    private func stopRunning() async {
        let session = session
        let sessionQueue = sessionQueue

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }

        isRunning = false
    }

    public func capturePhoto(to url: URL? = nil) async throws -> CapturedImage {
        guard isConfigured else {
            throw MultiModalKitError.captureSessionNotConfigured
        }

        let destinationURL = url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("captured-photo-\(UUID().uuidString)")
            .appendingPathExtension("jpg")

        let captureID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            let delegate = PhotoCaptureDelegate(destinationURL: destinationURL) { result in
                Task { @MainActor in
                    self.photoDelegates[captureID] = nil
                    continuation.resume(with: result)
                }
            }

            photoDelegates[captureID] = delegate
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let destinationURL: URL
    private let completion: (Result<CapturedImage, Error>) -> Void

    init(destinationURL: URL, completion: @escaping (Result<CapturedImage, Error>) -> Void) {
        self.destinationURL = destinationURL
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(MultiModalKitError.imageDataUnavailable))
            return
        }

        do {
            try data.write(to: destinationURL, options: [.atomic])
            completion(
                .success(
                    CapturedImage(
                        data: data,
                        temporaryFileURL: destinationURL,
                        contentType: .jpeg
                    )
                )
            )
        } catch {
            completion(.failure(error))
        }
    }
}
#endif
