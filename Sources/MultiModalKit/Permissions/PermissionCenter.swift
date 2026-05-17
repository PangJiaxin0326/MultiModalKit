@preconcurrency import AVFoundation
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
        var results: [MultiModalPermission: MultiModalPermissionStatus] = [:]
        for permission in permissions {
            results[permission] = await request(permission)
        }
        return results
    }

    public static func require(_ permission: MultiModalPermission) async throws {
        let current = status(for: permission)
        let finalStatus = current == .notDetermined ? await request(permission) : current
        guard finalStatus.isGranted else {
            throw MultiModalKitError.permissionDenied(permission)
        }
    }

    private static func requestAVAccess(for mediaType: AVMediaType) async -> MultiModalPermissionStatus {
        let current = AVCaptureDevice.authorizationStatus(for: mediaType)
        guard current == .notDetermined else {
            return mapAVAuthorizationStatus(current)
        }

        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: mediaType) { granted in
                continuation.resume(returning: granted)
            }
        }

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

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: accessLevel) { status in
                continuation.resume(returning: mapPhotoAuthorizationStatus(status))
            }
        }
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
