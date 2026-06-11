import Foundation

public enum MultiModalPermission: CaseIterable, Hashable, Identifiable, Sendable {
    case camera
    case microphone
    case speechRecognition
    case photoLibraryReadWrite
    case photoLibraryAddOnly

    public var id: Self { self }

    public var displayTitle: String {
        switch self {
        case .camera:
            MultiModalKitLocalization.string("Camera Access")
        case .microphone:
            MultiModalKitLocalization.string("Microphone Access")
        case .speechRecognition:
            MultiModalKitLocalization.string("Speech Recognition")
        case .photoLibraryReadWrite:
            MultiModalKitLocalization.string("Photo Library Access")
        case .photoLibraryAddOnly:
            MultiModalKitLocalization.string("Photo Library Add-Only Access")
        }
    }

    public var displayName: String {
        switch self {
        case .camera:
            MultiModalKitLocalization.string("camera")
        case .microphone:
            MultiModalKitLocalization.string("microphone")
        case .speechRecognition:
            MultiModalKitLocalization.string("speech recognition")
        case .photoLibraryReadWrite:
            MultiModalKitLocalization.string("photo library")
        case .photoLibraryAddOnly:
            MultiModalKitLocalization.string("photo library add-only access")
        }
    }

    public var symbolName: String {
        switch self {
        case .camera:
            "camera.fill"
        case .microphone:
            "microphone.fill"
        case .speechRecognition:
            "waveform.badge.mic"
        case .photoLibraryReadWrite:
            "photo.stack.fill"
        case .photoLibraryAddOnly:
            "photo.badge.plus.fill"
        }
    }

    public var privacyUsageDescriptionKey: String {
        switch self {
        case .camera:
            "NSCameraUsageDescription"
        case .microphone:
            "NSMicrophoneUsageDescription"
        case .speechRecognition:
            "NSSpeechRecognitionUsageDescription"
        case .photoLibraryReadWrite:
            "NSPhotoLibraryUsageDescription"
        case .photoLibraryAddOnly:
            "NSPhotoLibraryAddUsageDescription"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .camera:
            0
        case .microphone:
            1
        case .speechRecognition:
            2
        case .photoLibraryReadWrite:
            3
        case .photoLibraryAddOnly:
            4
        }
    }

    public static func ordered(_ permissions: some Sequence<Self>) -> [Self] {
        var seen: Set<Self> = []
        return permissions
            .filter { seen.insert($0).inserted }
            .sorted { lhs, rhs in
                lhs.sortOrder < rhs.sortOrder
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

    public var canRequestPermission: Bool {
        self == .notDetermined
    }

    public var shouldOpenSettings: Bool {
        switch self {
        case .denied:
            true
        case .notDetermined, .authorized, .limited, .restricted, .unavailable:
            false
        }
    }
}

public struct MultiModalPermissionState: Equatable, Hashable, Identifiable, Sendable {
    public var permission: MultiModalPermission
    public var status: MultiModalPermissionStatus

    public var id: MultiModalPermission { permission }

    public var isGranted: Bool { status.isGranted }

    public init(
        permission: MultiModalPermission,
        status: MultiModalPermissionStatus
    ) {
        self.permission = permission
        self.status = status
    }
}
