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

    /// Loads an image from a file on disk, copying it into `destinationDirectory`.
    ///
    /// The headless counterpart to ``loadPhoto(from:)-(PhotosPickerItem)``: it
    /// takes a file URL instead of a UI-driven picker selection, so callers
    /// without a `PhotosPicker` (e.g. tools) can still produce a ``PickedPhoto``.
    public func loadPhoto(from fileURL: URL) throws -> PickedPhoto {
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            throw MultiModalKitError.photoSelectionEmpty
        }

        let contentType = UTType(filenameExtension: fileURL.pathExtension)
        let fileExtension = contentType?.preferredFilenameExtension
            ?? (fileURL.pathExtension.isEmpty ? "image" : fileURL.pathExtension)
        let url = destinationDirectory
            .appendingPathComponent("picked-photo-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        try data.write(to: url, options: [.atomic])
        return PickedPhoto(data: data, temporaryFileURL: url, contentType: contentType)
    }
}
