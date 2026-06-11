import Foundation

/// Shared namespace for package metadata and small convenience values.
public enum MultiModalKit {
    public static let packageName = "MultiModalKit"

    /// Privacy keys commonly required by apps that use the package's permissioned APIs.
    public static let requiredPrivacyKeys = MultiModalPermission.allCases.map(\.privacyUsageDescriptionKey)
}
