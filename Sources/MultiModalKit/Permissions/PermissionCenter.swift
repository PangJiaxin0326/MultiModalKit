import AVFoundation
import CoreLocation
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
        case .locationWhenInUse, .locationAlways:
            mapLocationAuthorizationStatus(CLLocationManager().authorizationStatus, for: permission)
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
        case .locationWhenInUse, .locationAlways:
            await requestLocationAccess(for: permission)
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

    private static func requestLocationAccess(for permission: MultiModalPermission) async -> MultiModalPermissionStatus {
        let current = CLLocationManager().authorizationStatus
        // Always can still be *upgraded* from "when in use," so only short-circuit
        // when the user has made a terminal decision we cannot prompt past.
        switch current {
        case .denied, .restricted:
            return mapLocationAuthorizationStatus(current, for: permission)
        case .authorizedAlways:
            return .authorized
        case .authorizedWhenInUse where permission == .locationWhenInUse:
            return .authorized
        default:
            break
        }

        let requester = await LocationAuthorizationRequester(target: permission)
        let resolved = await requester.request()
        return mapLocationAuthorizationStatus(resolved, for: permission)
    }

    private static func mapLocationAuthorizationStatus(
        _ status: CLAuthorizationStatus,
        for permission: MultiModalPermission
    ) -> MultiModalPermissionStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorizedAlways:
            .authorized
        case .authorizedWhenInUse:
            // "When in use" is full grant for the when-in-use ask, but only a
            // partial grant when the caller needs always-on background access.
            permission == .locationAlways ? .limited : .authorized
        @unknown default:
            .unavailable
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

/// Bridges `CLLocationManager`'s delegate callback into a single `async` request.
/// Kept on the main actor so the manager is created and its delegate fires on the
/// run loop CoreLocation expects.
@MainActor
private final class LocationAuthorizationRequester: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let target: MultiModalPermission
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    init(target: MultiModalPermission) {
        self.target = target
        super.init()
        manager.delegate = self
    }

    func request() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            switch target {
            case .locationAlways:
                // visionOS has no "always" authorization; when-in-use is the deepest
                // grant the platform offers (mapped to `.limited` for this target).
                #if os(visionOS)
                manager.requestWhenInUseAuthorization()
                #else
                manager.requestAlwaysAuthorization()
                #endif
            default:
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            // Wait for the user to make a real choice; ignore the initial callback
            // that may still report `.notDetermined`.
            guard status != .notDetermined, let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: status)
        }
    }
}
