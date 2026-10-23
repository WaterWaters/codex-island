import Foundation
import Testing
@testable import IslandCore

@Test func settingsClampInvalidValuesAndNormalizeColors() {
    var values = IslandSettings()
    values.contentHeight = .infinity
    values.neonPrimary = "#aBc123"
    values.errorPulse = "javascript:void(0)"
    let clean = values.sanitized()
    #expect(clean.contentHeight == 72)
    #expect(clean.neonPrimary == "ABC123")
    #expect(clean.errorPulse == IslandSettings().errorPulse)
    values.contentHeight = 500
    #expect(values.sanitized().contentHeight == 140)
    values.contentHeight = -5
    #expect(values.sanitized().contentHeight == 60)
}

@Test func adjustedHeightPreservesNotchClearance() {
    let shape = IslandGeometry.layout(screenWidth: 1512, notchWidth: 180, notchHeight: 32, expanded: true, contentHeight: 120)
    #expect(shape.height == 152)
    #expect(shape.notchHeight == 32)
    let capsule = IslandGeometry.layout(screenWidth: 1512, notchWidth: 0, notchHeight: 0, expanded: true, contentHeight: 120)
    #expect(capsule.height == 120)
}

@Test func clickThroughLeaseExpiresAndCanBeReplacedOrCancelled() {
    let start = Date(timeIntervalSince1970: 1000)
    var lease = ClickThroughLease()
    #expect(!lease.isActive(now: start))
    lease.begin(now: start)
    #expect(lease.remainingSeconds(now: start) == 30)
    #expect(lease.remainingSeconds(now: start.addingTimeInterval(29.9)) == 1)
    #expect(!lease.isActive(now: start.addingTimeInterval(30)))
    lease.begin(now: start.addingTimeInterval(10))
    #expect(lease.remainingSeconds(now: start.addingTimeInterval(30)) == 10)
    lease.end()
    #expect(!lease.isActive(now: start))
}

@Test func synchronizedTimingControlsWalkingFramesAndRestDuration() throws {
    let frames = PetTimingProfile.compatibility.frames.mapValues { $0.map { $0 * 2 } }
    let timing = try PetTimingProfile(sourceVersion: "fixture-new", frames: frames)
    let walk = try #require(PetWalk(startX: 100, destinationX: 136, startedAt: Date(), timing: timing))
    #expect(walk.durationMilliseconds == 2120)
    #expect(walk.sample(elapsed: 0.13).frameIndex == 0)
    #expect(walk.sample(elapsed: 0.25).frameIndex == 1)
    #expect(walk.sample(elapsed: 1.06).positionX == 118)
    #expect(PetPlaybackPlan.restDurationMilliseconds(fraction: 0, idleDuration: timing.duration(for: .idle)) == 13200)
}

@Test func invalidTimingCannotReachThePlayer() {
    var frames = PetTimingProfile.compatibility.frames
    frames["walkingLeft"] = [0]
    #expect(throws: PetTimingProfile.TimingError.self) { try PetTimingProfile(sourceVersion: "fixture", frames: frames) }
}

@Test func oldPreferencesKeepAppearanceAndLeaveApprovalRecognitionOff() throws {
    let json = Data(#"{"schemaVersion":1,"isVisible":true,"selectedPetID":"fat","contentHeight":60,"animationsEnabled":true,"neonPrimary":"FD00FF","neonSecondary":"FF63B8","inputPulse":"FF63B8","errorPulse":"FF4757"}"#.utf8)
    let settings = try JSONDecoder().decode(IslandSettings.self, from: json).sanitized()
    #expect(settings.contentHeight == 60)
    #expect(settings.neonPrimary == "FD00FF")
    #expect(settings.approvalRecognitionEnabled != true)
    #expect(!settings.hideSessionTitle && !settings.shortcutEnabled)
    #expect(settings.language == .system)
    #expect(settings.appearancePreset == .custom)
    #expect(settings.preferredDisplayID == nil)
}

@Test func newPreferencesRoundTripWithoutLosingExistingChoices() throws {
    var settings = IslandSettings()
    settings.selectedPetID = "pet_synthetic"
    settings.neonPrimary = "123ABC"
    settings.approvalRecognitionEnabled = true
    settings.hideSessionTitle = true
    settings.shortcutEnabled = true
    settings.language = .ja
    settings.preferredDisplayID = "synthetic-display-uuid"
    settings.applyPreset(.quiet)
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(IslandSettings.self, from: data).sanitized()
    #expect(decoded == settings)
    #expect(decoded.selectedPetID == "pet_synthetic")
    #expect(decoded.approvalRecognitionEnabled == true)
}

@Test func unknownNewPreferencesFallBackWithoutResettingLegacyValues() throws {
    let json = Data(#"{"schemaVersion":1,"selectedPetID":"pet_synthetic","contentHeight":60,"neonPrimary":"FD00FF","approvalRecognitionEnabled":true,"language":"future-language","appearancePreset":"future-preset","preferredDisplayID":"unavailable-display"}"#.utf8)
    let settings = try JSONDecoder().decode(IslandSettings.self, from: json).sanitized()
    #expect(settings.language == .system && settings.appearancePreset == .custom)
    #expect(settings.selectedPetID == "pet_synthetic" && settings.neonPrimary == "FD00FF")
    #expect(settings.contentHeight == 60 && settings.approvalRecognitionEnabled == true)
    // An unplugged display is still a valid preference; runtime selection falls back.
    #expect(settings.preferredDisplayID == "unavailable-display")
}

@Test func appearancePresetsPreserveNonAppearancePreferencesAndCustomColors() {
    var settings = IslandSettings()
    settings.selectedPetID = "pet_synthetic"
    settings.contentHeight = 98
    settings.neonPrimary = "123ABC"
    settings.language = .zhHant
    settings.hideSessionTitle = true
    settings.shortcutEnabled = true
    settings.approvalRecognitionEnabled = true
    settings.preferredDisplayID = "synthetic-display"
    settings.applyPreset(.custom)
    #expect(settings.neonPrimary == "123ABC")
    for preset in [AppearancePreset.quiet, .highContrast, .standard] {
        settings.applyPreset(preset)
        #expect(settings.appearancePreset == preset)
        #expect(settings.selectedPetID == "pet_synthetic" && settings.contentHeight == 98)
        #expect(settings.language == .zhHant && settings.hideSessionTitle && settings.shortcutEnabled)
        #expect(settings.approvalRecognitionEnabled == true)
        #expect(settings.preferredDisplayID == "synthetic-display")
        #expect(settings.animationsEnabled == (preset == .standard))
        #expect(settings.sanitized() == settings)
    }
    #expect(settings.neonPrimary == IslandSettings().neonPrimary)
}

@Test func invalidLanguageAndDisplayValuesDoNotDiscardExistingAppearance() throws {
    let json = Data(#"{"selectedPetID":"pet_synthetic","neonPrimary":"FD00FF","language":42,"appearancePreset":{},"preferredDisplayID":"invalid\nidentifier"}"#.utf8)
    let settings = try JSONDecoder().decode(IslandSettings.self, from: json).sanitized()
    #expect(settings.language == .system && settings.appearancePreset == .custom)
    #expect(settings.preferredDisplayID == nil)
    #expect(settings.selectedPetID == "pet_synthetic" && settings.neonPrimary == "FD00FF")
}

@Test func languageResolutionHonorsOrderScriptAndManualOverride() {
    let examples: [([String], AppLanguage)] = [
        ([], .en), (["fr-FR", "de-DE"], .en),
        (["fr-FR", "ja-JP", "en-US"], .ja),
        (["en-GB", "zh-TW"], .en), (["ja", "zh-CN"], .ja),
        (["zh-Hans"], .zhHans), (["zh-CN"], .zhHans), (["zh-SG"], .zhHans),
        (["zh-Hant"], .zhHant), (["zh-TW"], .zhHant), (["zh-HK"], .zhHant),
        (["zh-MO"], .zhHant), (["zh"], .zhHans),
        (["zh-Hans-TW"], .zhHans), (["zh-Hant-CN"], .zhHant),
        (["ZH_hant_HK"], .zhHant), (["unknown", "", "en-US"], .en),
        (["english", "japanese", "zhang", "ja-JP"], .ja)
    ]
    for (languages, expected) in examples {
        #expect(AppLanguage.resolved(preference: .system, preferredLanguages: languages) == expected)
    }
    for preference in AppLanguage.allCases where preference != .system {
        #expect(AppLanguage.resolved(preference: preference, preferredLanguages: ["unknown"]) == preference)
    }
}

@Test func switchingBackToSystemAndResettingUseConservativeDefaults() throws {
    var settings = IslandSettings()
    settings.language = .zhHans
    settings.language = .system
    let decoded = try JSONDecoder().decode(IslandSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded.language == .system)
    let defaults = IslandSettings()
    #expect(!defaults.hideSessionTitle && !defaults.shortcutEnabled)
    #expect(defaults.approvalRecognitionEnabled != true)
    #expect(defaults.language == .system && defaults.preferredDisplayID == nil)
}

@Test func newPreferenceFieldsRemainReadableByThePreviousVersion() throws {
    // The previous synthesized decoder ignores added keys and still requires its
    // original v1 fields. Keep the encoded shape compatible with that decoder.
    struct LegacySettings: Decodable {
        let schemaVersion: Int
        let isVisible: Bool
        let selectedPetID: String
        let contentHeight: Double
        let animationsEnabled: Bool
        let neonPrimary: String
        let neonSecondary: String
        let inputPulse: String
        let errorPulse: String
        let approvalRecognitionEnabled: Bool?
    }
    var settings = IslandSettings()
    settings.selectedPetID = "pet_synthetic"
    settings.neonPrimary = "FD00FF"
    settings.hideSessionTitle = true
    settings.language = .ja
    let legacy = try JSONDecoder().decode(LegacySettings.self, from: JSONEncoder().encode(settings))
    #expect(legacy.schemaVersion == 1)
    #expect(legacy.selectedPetID == "pet_synthetic" && legacy.neonPrimary == "FD00FF")
    #expect(legacy.approvalRecognitionEnabled != true)
}

@Test func removedSystemPetMigratesWithoutLosingAppearanceOrCustomSelection() {
    var settings = IslandSettings()
    settings.selectedPetID = "system-icon"
    settings.contentHeight = 98
    settings.neonPrimary = "123ABC"
    let migrated = settings.sanitized()
    #expect(migrated.selectedPetID == "codex")
    #expect(migrated.contentHeight == 98 && migrated.neonPrimary == "123ABC")
    settings.selectedPetID = "pet_synthetic"
    #expect(settings.sanitized().selectedPetID == "pet_synthetic")
}

@Test func approvalRequiresEnabledPairedDecisionControls() {
    #expect(ApprovalControls.isPending([.init(label: "Allow once"), .init(label: "Deny")]))
    #expect(ApprovalControls.isPending([.init(label: "允许一次"), .init(label: "拒绝")]))
    #expect(!ApprovalControls.isPending([.init(label: "Allow once"), .init(label: "Deny", enabled: false)]))
    #expect(!ApprovalControls.isPending([.init(label: "请求批准的命令"), .init(label: "取消")]))
    #expect(!ApprovalControls.isPending([.init(label: "Allow once")]))
    #expect(!ApprovalControls.isPending(Array(repeating: .init(label: "Allow once"), count: 13) + [.init(label: "Deny")]))
}

@Test func explicitMotionOverrideLeavesAStaticPresetAndRetainsItsColors() {
    for preset in [AppearancePreset.quiet, .highContrast] {
        var settings = IslandSettings()
        settings.applyPreset(preset)
        let color = settings.neonPrimary
        settings.setAnimationsEnabled(false)
        #expect(settings.appearancePreset == preset)
        settings.setAnimationsEnabled(true)
        #expect(settings.appearancePreset == .custom)
        #expect(settings.animationsEnabled && settings.neonPrimary == color)
    }
}
