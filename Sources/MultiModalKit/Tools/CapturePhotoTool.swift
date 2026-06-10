import AIToolKit
import Foundation
import FoundationModels

/// Captures a still photo from the device camera.
///
/// The tool holds the ``CameraCaptureController`` it drives; the controller is
/// configured and started lazily on the first capture.
public struct CapturePhotoTool: Tool {
    @Generable
    public struct Input: Codable, Sendable {
        public var outputPath: String?

        public init(outputPath: String? = nil) {
            self.outputPath = outputPath
        }
    }

    @Generable
    public struct Output: Codable, Sendable {
        public var imagePath: String

        public init(imagePath: String) {
            self.imagePath = imagePath
        }
    }

    public static let toolName = "capture_photo"
    public static let toolDescription =
        "Captures a still photo from the device camera and saves it to disk."

    public var name: String { Self.toolName }
    public var description: String { Self.toolDescription }

    private let controller: CameraCaptureController

    public init(controller: CameraCaptureController) {
        self.controller = controller
    }

    public func call(arguments input: Input) async throws -> Output {
        try await PermissionCenter.require(.camera)
        try await controller.configure()
        await controller.start()

        let destination = input.outputPath.map { URL(filePath: $0) }
        let captured = try await controller.capturePhoto(to: destination)
        return Output(imagePath: captured.temporaryFileURL.path(percentEncoded: false))
    }
}
