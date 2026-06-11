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
    case audioConversionFailed
    case imageDataUnavailable
    case modelLoadFailed(String)
    case objectDetectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let feature):
            MultiModalKitLocalization.string("\(feature) is unavailable on this device.")
        case .permissionDenied(let permission):
            MultiModalKitLocalization.string("Permission denied for \(permission.displayName).")
        case .cameraNotFound:
            MultiModalKitLocalization.string("No compatible camera was found.")
        case .captureSessionNotConfigured:
            MultiModalKitLocalization.string("The camera capture session has not been configured.")
        case .captureFailed(let reason):
            MultiModalKitLocalization.string("Image capture failed: \(reason)")
        case .recordingFailed(let reason):
            MultiModalKitLocalization.string("Audio recording failed: \(reason)")
        case .photoSelectionEmpty:
            MultiModalKitLocalization.string("The selected photo did not contain transferable image data.")
        case .unsupportedSpeechLocale(let identifier):
            MultiModalKitLocalization.string("Speech transcription does not support locale \(identifier).")
        case .speechAssetsUnavailable:
            MultiModalKitLocalization.string("Speech model assets are unavailable.")
        case .speechUnavailable:
            MultiModalKitLocalization.string("Speech transcription is unavailable on this device.")
        case .audioConversionFailed:
            MultiModalKitLocalization.string("Microphone audio could not be converted for analysis.")
        case .imageDataUnavailable:
            MultiModalKitLocalization.string("Image data is unavailable.")
        case .modelLoadFailed(let reason):
            MultiModalKitLocalization.string("Model could not be loaded: \(reason)")
        case .objectDetectionFailed(let reason):
            MultiModalKitLocalization.string("Object detection failed: \(reason)")
        }
    }
}
