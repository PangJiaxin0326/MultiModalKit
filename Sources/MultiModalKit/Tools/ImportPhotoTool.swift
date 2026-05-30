import AIToolKit
import Foundation

/// Imports an image file into the app's working directory.
public struct ImportPhotoTool: Tool {
    public struct Input: Codable, Sendable {
        public var imagePath: String

        public init(imagePath: String) {
            self.imagePath = imagePath
        }
    }

    public struct Output: Codable, Sendable {
        public var importedPath: String
        public var contentType: String?
        public var byteCount: Int

        public init(importedPath: String, contentType: String? = nil, byteCount: Int) {
            self.importedPath = importedPath
            self.contentType = contentType
            self.byteCount = byteCount
        }
    }

    public static let name = "import_photo"
    public static let description =
        "Imports an image file from disk, copying it into the app's working "
        + "directory and reporting its content type and size."
    public static let inputSchema = ToolSchema.object(
        properties: [
            "imagePath": .string(
                description: "Absolute file path to the image to import."
            ),
        ],
        required: ["imagePath"]
    )

    public init() {}

    public func call(_ input: Input, in context: ToolContext) async throws -> Output {
        let service = PhotoLibraryService()
        let photo = try service.loadPhoto(from: URL(filePath: input.imagePath))
        return Output(
            importedPath: photo.temporaryFileURL.path(percentEncoded: false),
            contentType: photo.contentType?.identifier,
            byteCount: photo.data.count
        )
    }
}
