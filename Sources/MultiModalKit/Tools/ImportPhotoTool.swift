import AIToolKit
import Foundation
import FoundationModels

/// Imports an image file into the app's working directory.
public struct ImportPhotoTool: Tool {
    @Generable
    public struct Input: Codable, Sendable {
        public var imagePath: String

        public init(imagePath: String) {
            self.imagePath = imagePath
        }
    }

    @Generable
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

    public static let toolName = "import_photo"
    public static let toolDescription =
        "Imports an image file from disk, copying it into the app's working "
        + "directory and reporting its content type and size."

    public var name: String { Self.toolName }
    public var description: String { Self.toolDescription }

    public init() {}

    public func call(arguments input: Input) async throws -> Output {
        let service = PhotoLibraryService()
        let photo = try service.loadPhoto(from: URL(filePath: input.imagePath))
        return Output(
            importedPath: photo.temporaryFileURL.path(percentEncoded: false),
            contentType: photo.contentType?.identifier,
            byteCount: photo.data.count
        )
    }
}
