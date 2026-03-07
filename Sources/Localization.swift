import Foundation

enum L10n {
    static func supportedLanguageCode() -> String {
        let languageIdentifier = effectiveLanguageIdentifier().lowercased()
        return languageIdentifier.hasPrefix("de") ? "de" : "en"
    }

    static func s(_ key: String) -> String {
        let languageCode = supportedLanguageCode()
        let localizedBundle = bundle(for: languageCode)
        let localized = NSLocalizedString(
            key,
            tableName: nil,
            bundle: localizedBundle,
            value: key,
            comment: "")
        if localized != key {
            return localized
        }

        // Explicit fallback to English when a key is missing or language is unsupported.
        let englishBundle = bundle(for: "en")
        return NSLocalizedString(
            key,
            tableName: nil,
            bundle: englishBundle,
            value: key,
            comment: "")
    }

    private static func effectiveLanguageIdentifier() -> String {
        #if DEBUG
            if let override = UserDefaults.standard.string(forKey: "debug.locale.override") {
                switch override {
                case "de":
                    return "de"
                case "en":
                    return "en"
                default:
                    break
                }
            }
        #endif
        return Locale.preferredLanguages.first ?? "en"
    }

    private static func bundle(for languageCode: String) -> Bundle {
        if let path = Bundle.module.path(forResource: languageCode, ofType: "lproj"),
            let bundle = Bundle(path: path)
        {
            return bundle
        }
        return .module
    }
}
