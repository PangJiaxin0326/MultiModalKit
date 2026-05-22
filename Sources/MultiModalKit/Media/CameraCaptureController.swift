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
        throw MultiModalKitError.unavailable("Camera photo capture")
    }

    public func start() {
        isRunning = false
    }

    public func stop() {
        isRunning = false
    }

    public func capturePhoto(to url: URL? = nil) async throws -> CapturedImage {
        throw MultiModalKitError.unavailable("Camera photo capture")
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
    private var photoDelegate: PhotoCaptureDelegate?

    public override init() {
        super.init()
    }

    public func configure() throws {
        guard !isConfigured else {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }

        guard let camera = AVCaptureDevice.default(for: .video) else {
            throw MultiModalKitError.cameraNotFound
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw MultiModalKitError.captureFailed("The camera input or photo output could not be added.")
        }

        session.addInput(input)
        session.addOutput(photoOutput)
        isConfigured = true
    }

    public func start() {
        guard isConfigured else {
            isRunning = false
            return
        }

        sessionQueue.async { [session] in
            guard !session.isRunning else {
                Task { @MainActor in
                    self.isRunning = true
                }
                return
            }

            session.startRunning()

            Task { @MainActor in
                self.isRunning = session.isRunning
            }
        }
    }

    public func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }

            Task { @MainActor in
                self.isRunning = false
            }
        }
    }

    public func capturePhoto(to url: URL? = nil) async throws -> CapturedImage {
        guard isConfigured else {
            throw MultiModalKitError.captureSessionNotConfigured
        }

        let destinationURL = url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("captured-photo-\(UUID().uuidString)")
            .appendingPathExtension("jpg")

        return try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            let delegate = PhotoCaptureDelegate(destinationURL: destinationURL) { result in
                Task { @MainActor in
                    self.photoDelegate = nil
                    continuation.resume(with: result)
                }
            }

            photoDelegate = delegate
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
