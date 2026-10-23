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
