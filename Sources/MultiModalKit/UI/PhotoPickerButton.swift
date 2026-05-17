import Foundation
@preconcurrency import PhotosUI
@preconcurrency import SwiftUI

@MainActor
public struct PhotoPickerButton: View {
    @Binding private var photo: PickedPhoto?
    @Binding private var photoURL: URL?

    @State private var selectedItem: PhotosPickerItem?
    @State private var errorMessage: String?

    private let title: String
    private let systemImage: String
    private let service: PhotoLibraryService
    private let onPick: (@MainActor (PickedPhoto) -> Void)?

    public init(
        title: String = "Choose Photo",
        systemImage: String = "photo.on.rectangle",
        photo: Binding<PickedPhoto?> = .constant(nil),
        photoURL: Binding<URL?> = .constant(nil),
        service: PhotoLibraryService = PhotoLibraryService(),
        onPick: (@MainActor (PickedPhoto) -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        _photo = photo
        _photoURL = photoURL
        self.service = service
        self.onPick = onPick
    }

    public var body: some View {
        let title = title
        let systemImage = systemImage

        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label(title, systemImage: systemImage)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: selectedItem) {
            guard let selectedItem else {
                return
            }

            do {
                let pickedPhoto = try await service.loadPhoto(from: selectedItem)
                photo = pickedPhoto
                photoURL = pickedPhoto.temporaryFileURL
                onPick?(pickedPhoto)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
