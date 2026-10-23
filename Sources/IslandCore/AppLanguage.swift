import Foundation

/// Persisted UI preference. Protocol values and source data never depend on it.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system
    case en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case ja

    /// Language names remain recognizable regardless of the current UI language.
    public var displayName: String {
        switch self {
        case .system: "System"
        case .en: "English"
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .ja: "日本語"
        }
    }

    public static func resolved(preference: Self, preferredLanguages: [String]) -> Self {
        guard preference == .system else { return preference }
        for identifier in preferredLanguages {
            let components = identifier.replacingOccurrences(of: "_", with: "-")
                .lowercased().split(separator: "-")
            guard let language = components.first else { continue }
            switch language {
            case "en": return .en
            case "ja": return .ja
            case "zh":
                // Explicit script has priority even when the region disagrees.
                if components.contains("hans") { return .zhHans }
                if components.contains("hant") { return .zhHant }
                if components.contains(where: { ["tw", "hk", "mo"].contains($0) }) { return .zhHant }
                return .zhHans
            default: continue
            }
        }
        return .en
    }
}

public enum AppearancePreset: String, Codable, CaseIterable, Sendable {
    case custom, standard, quiet, highContrast
}
