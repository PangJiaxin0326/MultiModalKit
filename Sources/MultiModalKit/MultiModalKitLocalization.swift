import Foundation

enum MultiModalKitLocalization {
    static func string(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: .module)
    }
}
