import Foundation

public enum MultiModalKitError: Error, Equatable, LocalizedError, Sendable {
    case unavailable(String)
    case permissionDenied(MultiModalPermission)
    case cameraNotFound
    case captureSessionNotConfigured
    case captureFailed(String)
    case recordingFailed(String)
    case photoSelectionEmpty
    case unsupportedSpeechLocale(String)
    case speechAssetsUnavailable
    case speechUnavailable
    case imageDataUnavailable

    public var errorDescription: String? {
        switch self {
        case .unavailable(let feature):
            "\(feature) is unavailable on this device."
        case .permissionDenied(let permission):
            "Permission denied for \(permission.displayName)."
        case .cameraNotFound:
            "No compatible camera was found."
        case .captureSessionNotConfigured:
            "The camera capture session has not been configured."
        case .captureFailed(let reason):
            "Image capture failed: \(reason)"
        case .recordingFailed(let reason):
            "Audio recording failed: \(reason)"
        case .photoSelectionEmpty:
            "The selected photo did not contain transferable image data."
        case .unsupportedSpeechLocale(let identifier):
            "Speech transcription does not support locale \(identifier)."
        case .speechAssetsUnavailable:
            "Speech model assets are unavailable."
        case .speechUnavailable:
            "Speech transcription is unavailable on this device."
        case .imageDataUnavailable:
            "Image data is unavailable."
        }
    }
}
