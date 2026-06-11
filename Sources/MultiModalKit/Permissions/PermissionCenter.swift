import AVFoundation
import Foundation
import Photos
import Speech

public enum PermissionCenter {
    public static func status(for permission: MultiModalPermission) -> MultiModalPermissionStatus {
        switch permission {
        case .camera:
            mapAVAuthorizationStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            mapAVAuthorizationStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        case .speechRecognition:
            mapSpeechAuthorizationStatus(SFSpeechRecognizer.authorizationStatus())
        case .photoLibraryReadWrite:
            mapPhotoAuthorizationStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .photoLibraryAddOnly:
            mapPhotoAuthorizationStatus(PHPhotoLibrary.authorizationStatus(for: .addOnly))
        }
    }

    public static func status(for permissions: [MultiModalPermission]) -> [MultiModalPermission: MultiModalPermissionStatus] {
        Dictionary(
            uniqueKeysWithValues: MultiModalPermission.ordered(permissions).map { permission in
                (permission, status(for: permission))
            }
        )
    }

    public static func states(for permissions: [MultiModalPermission]) -> [MultiModalPermissionState] {
        MultiModalPermission.ordered(permissions).map { permission in
            MultiModalPermissionState(
                permission: permission,
                status: status(for: permission)
            )
        }
    }

    @discardableResult
    public static func request(_ permission: MultiModalPermission) async -> MultiModalPermissionStatus {
        switch permission {
        case .camera:
            await requestAVAccess(for: .video)
        case .microphone:
            await requestAVAccess(for: .audio)
        case .speechRecognition:
            await requestSpeechRecognition()
        case .photoLibraryReadWrite:
            await requestPhotoLibraryAccess(for: .readWrite)
        case .photoLibraryAddOnly:
            await requestPhotoLibraryAccess(for: .addOnly)
        }
    }

    @discardableResult
    public static func request(_ permissions: [MultiModalPermission]) async -> [MultiModalPermission: MultiModalPermissionStatus] {
        Dictionary(
            uniqueKeysWithValues: await requestStates(for: permissions).map { state in
                (state.permission, state.status)
            }
        )
    }

    @discardableResult
    public static func requestStates(for permissions: [MultiModalPermission]) async -> [MultiModalPermissionState] {
        var states: [MultiModalPermissionState] = []
        for permission in MultiModalPermission.ordered(permissions) {
            let status = await request(permission)
            states.append(
                MultiModalPermissionState(
                    permission: permission,
                    status: status
                )
            )
        }
        return states
    }

    public static func require(_ permission: MultiModalPermission) async throws {
        let current = status(for: permission)
        let finalStatus = current == .notDetermined ? await request(permission) : current
        guard finalStatus.isGranted else {
            throw MultiModalKitError.permissionDenied(permission)
        }
    }

    public static func require(_ permissions: [MultiModalPermission]) async throws {
        for permission in MultiModalPermission.ordered(permissions) {
            try await require(permission)
        }
    }

    private static func requestAVAccess(for mediaType: AVMediaType) async -> MultiModalPermissionStatus {
        let current = AVCaptureDevice.authorizationStatus(for: mediaType)
        guard current == .notDetermined else {
            return mapAVAuthorizationStatus(current)
        }

        let granted = await AVCaptureDevice.requestAccess(for: mediaType)

        return granted ? .authorized : mapAVAuthorizationStatus(AVCaptureDevice.authorizationStatus(for: mediaType))
    }

    private static func requestSpeechRecognition() async -> MultiModalPermissionStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else {
            return mapSpeechAuthorizationStatus(current)
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: mapSpeechAuthorizationStatus(status))
            }
        }
    }

    private static func requestPhotoLibraryAccess(for accessLevel: PHAccessLevel) async -> MultiModalPermissionStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: accessLevel)
        guard current == .notDetermined else {
            return mapPhotoAuthorizationStatus(current)
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: accessLevel)
        return mapPhotoAuthorizationStatus(status)
    }

    private static func mapAVAuthorizationStatus(_ status: AVAuthorizationStatus) -> MultiModalPermissionStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .authorized
        @unknown default:
            .unavailable
        }
    }

    private static func mapSpeechAuthorizationStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> MultiModalPermissionStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .authorized:
            .authorized
        @unknown default:
            .unavailable
        }
    }

    private static func mapPhotoAuthorizationStatus(_ status: PHAuthorizationStatus) -> MultiModalPermissionStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .limited:
            .limited
        @unknown default:
            .unavailable
        }
    }
}
