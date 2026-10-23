import Foundation

public struct IslandSettings: Codable, Equatable, Sendable {
    public static let defaultPetID = "codex"
    public var schemaVersion = 1
    public var isVisible = true
    public var selectedPetID = defaultPetID
    public var contentHeight = 72.0
    public var animationsEnabled = true
    public var neonPrimary = "66E6FF"
    public var neonSecondary = "FF63B8"
    public var inputPulse = "FF63B8"
    public var errorPulse = "FF4757"
    // Optional preserves v1 preferences written before the permission feature.
    public var approvalRecognitionEnabled: Bool?
    public var hideSessionTitle = false
    public var language: AppLanguage = .system
    public var preferredDisplayID: String?
    // Existing v1 colors are custom preferences, including when they match defaults.
    public var appearancePreset: AppearancePreset = .custom
    public var shortcutEnabled = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, isVisible, selectedPetID, contentHeight, animationsEnabled
        case neonPrimary, neonSecondary, inputPulse, errorPulse, approvalRecognitionEnabled
        case hideSessionTitle, language, preferredDisplayID, appearancePreset, shortcutEnabled
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? schemaVersion
        isVisible = try values.decodeIfPresent(Bool.self, forKey: .isVisible) ?? isVisible
        selectedPetID = try values.decodeIfPresent(String.self, forKey: .selectedPetID) ?? selectedPetID
        contentHeight = try values.decodeIfPresent(Double.self, forKey: .contentHeight) ?? contentHeight
        animationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .animationsEnabled) ?? animationsEnabled
        neonPrimary = try values.decodeIfPresent(String.self, forKey: .neonPrimary) ?? neonPrimary
        neonSecondary = try values.decodeIfPresent(String.self, forKey: .neonSecondary) ?? neonSecondary
        inputPulse = try values.decodeIfPresent(String.self, forKey: .inputPulse) ?? inputPulse
        errorPulse = try values.decodeIfPresent(String.self, forKey: .errorPulse) ?? errorPulse
        approvalRecognitionEnabled = try values.decodeIfPresent(Bool.self, forKey: .approvalRecognitionEnabled)
        hideSessionTitle = try values.decodeIfPresent(Bool.self, forKey: .hideSessionTitle) ?? false
        language = (try? values.decode(String.self, forKey: .language)).flatMap(AppLanguage.init(rawValue:)) ?? .system
        preferredDisplayID = try values.decodeIfPresent(String.self, forKey: .preferredDisplayID)
        appearancePreset = (try? values.decode(String.self, forKey: .appearancePreset)).flatMap(AppearancePreset.init(rawValue:)) ?? .custom
        shortcutEnabled = try values.decodeIfPresent(Bool.self, forKey: .shortcutEnabled) ?? false
    }

    public func sanitized() -> Self {
        guard schemaVersion == 1 else { return Self() }
        var copy = self
        copy.contentHeight = contentHeight.isFinite ? min(140, max(60, contentHeight)) : 72
        if selectedPetID.isEmpty || selectedPetID.count > 200 || selectedPetID == "system-icon" {
            copy.selectedPetID = Self.defaultPetID
        }
        let fallback = Self()
        copy.neonPrimary = Self.validatedHex(neonPrimary) ?? fallback.neonPrimary
        copy.neonSecondary = Self.validatedHex(neonSecondary) ?? fallback.neonSecondary
        copy.inputPulse = Self.validatedHex(inputPulse) ?? fallback.inputPulse
        copy.errorPulse = Self.validatedHex(errorPulse) ?? fallback.errorPulse
        if let id = preferredDisplayID,
           id.isEmpty || id.count > 200 || id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            copy.preferredDisplayID = nil
        }
        return copy
    }

    /// Changes only appearance; session, permission and display preferences survive.
    public mutating func applyPreset(_ preset: AppearancePreset) {
        appearancePreset = preset
        switch preset {
        case .custom:
            break
        case .standard:
            let defaults = Self()
            neonPrimary = defaults.neonPrimary
            neonSecondary = defaults.neonSecondary
            inputPulse = defaults.inputPulse
            errorPulse = defaults.errorPulse
            animationsEnabled = true
        case .quiet:
            neonPrimary = "A8C4CC"
            neonSecondary = "C0B4CC"
            inputPulse = "D8C69B"
            errorPulse = "E7A3A3"
            animationsEnabled = false
        case .highContrast:
            neonPrimary = "FFFFFF"
            neonSecondary = "FFFFFF"
            inputPulse = "FFFF00"
            errorPulse = "FF8080"
            animationsEnabled = false
        }
    }

    /// An explicit motion override leaves the static preset visibly behind.
    public mutating func setAnimationsEnabled(_ enabled: Bool) {
        if enabled && (appearancePreset == .quiet || appearancePreset == .highContrast) {
            appearancePreset = .custom
        }
        animationsEnabled = enabled
    }

    public static func validatedHex(_ value: String) -> String? {
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6, hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        return hex.uppercased()
    }
}

/// An ephemeral lease; never serialized with appearance preferences.
public struct ClickThroughLease: Sendable {
    public private(set) var expiresAt: Date?
    public init() {}
    public mutating func begin(now: Date) { expiresAt = now.addingTimeInterval(30) }
    public mutating func end() { expiresAt = nil }
    public func remainingSeconds(now: Date) -> Int {
        guard let expiresAt else { return 0 }
        return Int(ceil(min(30, max(0, expiresAt.timeIntervalSince(now)))))
    }
    public func isActive(now: Date) -> Bool { remainingSeconds(now: now) > 0 }
}
