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

    public init() {}

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
        return copy
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
