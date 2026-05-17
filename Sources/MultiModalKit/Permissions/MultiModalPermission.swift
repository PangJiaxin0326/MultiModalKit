import Foundation

public enum MultiModalPermission: CaseIterable, Hashable, Identifiable, Sendable {
    case camera
    case microphone
    case speechRecognition
    case photoLibraryReadWrite
    case photoLibraryAddOnly

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .camera:
            "camera"
        case .microphone:
            "microphone"
        case .speechRecognition:
            "speech recognition"
        case .photoLibraryReadWrite:
            "photo library"
        case .photoLibraryAddOnly:
            "photo library add-only access"
        }
    }
}

public enum MultiModalPermissionStatus: Equatable, Hashable, Sendable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted
    case unavailable

    public var isGranted: Bool {
        switch self {
        case .authorized, .limited:
            true
        case .notDetermined, .denied, .restricted, .unavailable:
            false
        }
    }
}
