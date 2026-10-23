import Foundation
import IslandCore
import Observation

/// Translation is confined to display boundaries; source state and identifiers
/// remain unchanged when the user switches language.
@MainActor @Observable
final class L10n {
    static let shared = L10n()
    private static let bundles: [String: Bundle] = {
        var result: [String: Bundle] = [:]
        for language in ["en", "zh-Hans", "zh-Hant", "ja"] {
            if let bundle = Bundle.module.url(forResource: language, withExtension: "lproj").flatMap(Bundle.init(url:)) {
                result[language] = bundle
            }
        }
        return result
    }()
    private(set) var language: AppLanguage = .en
    var locale: Locale { Locale(identifier: language.rawValue) }

    func configure(language: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.language = AppLanguage.resolved(preference: language, preferredLanguages: preferredLanguages)
    }

    static func text(_ source: String) -> String {
        guard let key = LocalizationSources.keys[source] else { return source }
        return value(key)
    }

    static func value(_ key: String) -> String {
        let language = shared.language.rawValue
        let english = localizedBundle("en")?.localizedString(forKey: key, value: key, table: nil) ?? key
        return localizedBundle(language)?.localizedString(forKey: key, value: english, table: nil) ?? english
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: value(key), locale: shared.locale, arguments: arguments)
    }

    static func count(_ key: String, _ count: Int) -> String {
        String(format: value(key + (count == 1 ? ".one" : ".many")), locale: shared.locale, arguments: [count])
    }

    static func localizedBundle(_ language: String) -> Bundle? {
        bundles[language]
    }
}
