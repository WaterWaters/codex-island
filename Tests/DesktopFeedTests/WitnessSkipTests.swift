import Foundation
import Testing
@testable import DesktopFeed

/// Local copy of the fixture event builder from the shared private helpers.
private func event(_ type: String, call: String, name: String? = nil, turn: String? = nil) -> Data {
    var payload = ["type": type, "call_id": call]
    payload["name"] = name
    payload["turn_id"] = turn
    return try! JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": payload])
}

/// A sendable box so the injectable stamp closure observes test mutations.
private final class StampBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [DatabaseStamp]?
    init(_ initial: [DatabaseStamp]?) { value = initial }

    func set(_ value: [DatabaseStamp]?) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }

    func get() -> [DatabaseStamp]? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// The witness skip must reuse only byte-identical catalog evidence; any
/// rollout append or stamp change still surfaces on the very next read.
@Test func witnessSkipReusesUnchangedBytesAndCapForcesFreshQuery() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    let feed = LocalSessionFeed(home: fixture.root, stampsFor: { _ in
        [DatabaseStamp(device: 1, inode: 2, size: 0, modifiedSeconds: 0, modifiedNanoseconds: 0)]
    }, maximumSkip: .seconds(30))
    let now = ContinuousClock.now
    let first = try await feed.read(at: now)
    #expect(first.snapshot.activities == [.running])
    #expect(first.caughtUp)
    // Identical claimed catalog bytes: the reuse path returns the prior
    // observation even though the real catalog changed.
    try fixture.execute("state", "UPDATE threads SET title='新标题'")
    let reused = try await feed.read(at: now.advanced(by: .seconds(5)))
    #expect(reused.snapshot.sessionTitle == first.snapshot.sessionTitle)
    #expect(reused.snapshot.observedAt > first.snapshot.observedAt)
    // Past the skip horizon the forced fresh query must see the change.
    let refreshed = try await feed.read(at: now.advanced(by: .seconds(40)))
    #expect(refreshed.snapshot.sessionTitle == "新标题")
}

@Test func witnessSetChangeForcesImmediateRequery() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    let box = StampBox([DatabaseStamp(device: 1, inode: 2, size: 0, modifiedSeconds: 0, modifiedNanoseconds: 0)])
    let feed = LocalSessionFeed(home: fixture.root, stampsFor: { _ in box.get() }, maximumSkip: .seconds(30))
    let now = ContinuousClock.now
    _ = try await feed.read(at: now)
    try fixture.execute("state", "UPDATE threads SET title='替换标题'")
    box.set([DatabaseStamp(device: 1, inode: 3, size: 1, modifiedSeconds: 100, modifiedNanoseconds: 1)])
    let refreshed = try await feed.read(at: now.advanced(by: .seconds(5)))
    #expect(refreshed.snapshot.sessionTitle == "替换标题")
}

/// New rollout bytes must not hide behind an unchanged database even when the
/// catalog believes the session is still current.
@Test func rolloutAppendsContinueFeedingTheWitness() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    let feed = LocalSessionFeed(home: fixture.root)
    let now = ContinuousClock.now
    let first = try await feed.read(at: now)
    #expect(first.snapshot.activities == [.running])
    try fixture.append(event("function_call", call: "q", name: "request_user_input"), id: "a")
    let second = try await feed.read(at: now.advanced(by: .seconds(2)))
    #expect(second.snapshot.activities == [.needsInput])
}

