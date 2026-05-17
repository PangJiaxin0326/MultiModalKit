import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

public struct PhotoLibraryService: Sendable {
    public var destinationDirectory: URL

    public init(destinationDirectory: URL = FileManager.default.temporaryDirectory) {
        self.destinationDirectory = destinationDirectory
    }

    public func loadPhoto(from item: PhotosPickerItem) async throws -> PickedPhoto {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw MultiModalKitError.photoSelectionEmpty
        }

        let contentType = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }) ?? item.supportedContentTypes.first
        let fileExtension = contentType?.preferredFilenameExtension ?? "image"
        let url = destinationDirectory
            .appendingPathComponent("picked-photo-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        try data.write(to: url, options: [.atomic])
        return PickedPhoto(data: data, temporaryFileURL: url, contentType: contentType)
    }
}
