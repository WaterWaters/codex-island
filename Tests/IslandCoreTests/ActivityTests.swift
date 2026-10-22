import Foundation
import Testing
@testable import IslandCore

private let now = Date(timeIntervalSince1970: 1_792_540_800)

private func snapshot(_ states: [WorkState], session: String = "a", age: TimeInterval = 0,
                      complete: Bool = true, version: Int = 1) -> ActivitySnapshot {
    ActivitySnapshot(source: "fixture", sessionID: session, observedAt: now.addingTimeInterval(-age),
                     isComplete: complete, activities: states, schemaVersion: version)
}

@Test func priorityMatchesPetSemantics() {
    #expect(ActivitySummary.reduce([.running, .ready, .blocked, .needsInput]).state == .needsInput)
    #expect(ActivitySummary.reduce([.running, .ready, .blocked]).state == .blocked)
    #expect(ActivitySummary.reduce([.running, .ready]).state == .ready)
    #expect(ActivitySummary.reduce([.running]).state == .running)
    #expect(ActivitySummary.reduce([]).state == .idle)
}

@Test func backgroundWorkRemainsVisibleInSummary() {
    let summary = ActivitySummary.reduce([.running, .needsInput, .running])
    #expect(summary.runningCount == 2)
    #expect(summary.detail == "另有 2 项运行中")
}

@Test func unreadReadyDoesNotExpireInReducer() throws {
    var gate = SnapshotGate()
    let first = try gate.accept(snapshot([.ready]), now: now)
    let refreshed = ActivitySnapshot(source: "fixture", sessionID: "a", observedAt: now.addingTimeInterval(3600), activities: [.ready])
    let later = try gate.accept(refreshed, now: now.addingTimeInterval(3600))
    #expect(first.state == .ready)
    #expect(later.state == .ready)
}

@Test func incompleteDataCannotBecomeIdle() {
    #expect(throws: SnapshotError.incomplete) { try snapshot([], complete: false).validated(now: now) }
    #expect(throws: SnapshotError.incomplete) { try snapshot([.idle]).validated(now: now) }
}

@Test func staleAndFutureSnapshotsAreRejected() {
    #expect(throws: SnapshotError.stale) { try snapshot([.running], age: 31).validated(now: now) }
    #expect(throws: SnapshotError.stale) { try snapshot([.ready], age: -6).validated(now: now) }
}

@Test func unknownSchemaIsRejected() {
    #expect(throws: SnapshotError.unsupportedVersion) { try snapshot([], version: 2).validated(now: now) }
}

@Test func outOfOrderUpdateCannotClearRunning() throws {
    var gate = SnapshotGate()
    _ = try gate.accept(snapshot([.running]), now: now)
    #expect(throws: SnapshotError.outOfOrder) { try gate.accept(snapshot([], age: 1), now: now) }
}

@Test func retiredSessionCannotOverwriteNewSession() throws {
    var gate = SnapshotGate()
    _ = try gate.accept(snapshot([.ready]), now: now)
    _ = try gate.accept(snapshot([.running], session: "b", age: -1), now: now.addingTimeInterval(1))
    #expect(throws: SnapshotError.retiredSession) {
        try gate.accept(snapshot([], session: "a", age: -2), now: now.addingTimeInterval(2))
    }
}

@Test func duplicateSnapshotsAreIdempotent() throws {
    var gate = SnapshotGate()
    let value = snapshot([.running])
    #expect(try gate.accept(value, now: now) == gate.accept(value, now: now))
}

@Test func malformedStateCannotDefaultToSuccess() {
    let json = """
    {"schemaVersion":1,"source":"fixture","sessionID":"a","observedAt":"2026-10-21T02:00:00Z","isComplete":true,"activities":["new-unknown-state"]}
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(throws: DecodingError.self) { try decoder.decode(ActivitySnapshot.self, from: Data(json.utf8)) }
}

@Test func notchedGeometryKeepsCameraHousingEmpty() {
    let compact = IslandGeometry.layout(screenWidth: 1512, notchWidth: 180, notchHeight: 32, expanded: false)
    let expanded = IslandGeometry.layout(screenWidth: 1512, notchWidth: 180, notchHeight: 32, expanded: true)
    #expect(compact.hasNotch)
    #expect(compact.width >= compact.notchWidth + 96)
    #expect(expanded.height > compact.height)
    #expect(expanded.height >= expanded.notchHeight + 44)
}

@Test func externalDisplayUsesCapsuleAndClampsWidth() {
    let layout = IslandGeometry.layout(screenWidth: 2560, notchWidth: 0, notchHeight: 0, expanded: false)
    #expect(!layout.hasNotch)
    #expect(layout.height == 44)
    let narrow = IslandGeometry.layout(screenWidth: 280, notchWidth: 0, notchHeight: 0, expanded: true)
    #expect(narrow.width <= 248)
}

@Test func oldExternalSnapshotStillDecodesWithoutDisplayMetadata() throws {
    let raw = #"{"schemaVersion":1,"source":"fixture","sessionID":"a","observedAt":"2026-10-21T02:00:00Z","isComplete":true,"activities":[]}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let value = try decoder.decode(ActivitySnapshot.self, from: Data(raw.utf8))
    #expect(value.activity == nil)
    #expect(value.sessionTitle == nil)
}

@Test func activityLabelsDistinguishRunningAndFinishedCommands() {
    #expect(SessionActivity.from(itemType: "commandExecution", status: "inProgress").title == "正在运行命令")
    #expect(SessionActivity.from(itemType: "commandExecution", status: "completed").title == "已运行命令")
    #expect(SessionActivity.from(itemType: "reasoning", status: nil) == .thinking)
    #expect(SessionActivity.from(itemType: "futureType", status: nil) == .working)
}

@Test func displayTitleIsBoundedAndSingleLine() {
    let value = ActivitySnapshot(source: "fixture", sessionID: "s", observedAt: now, activities: [],
                                 sessionTitle: "  会话\n标题  " + String(repeating: "长", count: 300))
    #expect(value.displaySessionTitle?.contains("\n") == false)
    #expect(value.displaySessionTitle?.count == 160)
}
