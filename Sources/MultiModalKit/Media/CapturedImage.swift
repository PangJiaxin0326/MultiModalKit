import Foundation
import UniformTypeIdentifiers

public struct CapturedImage: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var data: Data
    public var temporaryFileURL: URL
    public var contentType: UTType

    public init(
        id: UUID = UUID(),
        data: Data,
        temporaryFileURL: URL,
        contentType: UTType = .jpeg
    ) {
        self.id = id
        self.data = data
        self.temporaryFileURL = temporaryFileURL
        self.contentType = contentType
    }
}
