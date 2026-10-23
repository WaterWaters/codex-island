@testable import DesktopFeed
import Testing

@Test(arguments: [["a", "z"], ["z", "a"]])
func idleFocusWithEqualActivityIsStableAcrossDatabaseOrder(insertionOrder: [String]) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    for id in insertionOrder {
        try fixture.add(id: id, status: "completed", title: "Synthetic \(id)", startedAt: 1000)
    }
    let feed = LocalSessionFeed(home: fixture.root)
    let initial = try await feed.read().snapshot
    #expect(initial.activities.isEmpty)
    #expect(initial.activity == .idle)
    #expect(initial.sessionTitle == "Synthetic z")
    await feed.reset()
    #expect(try await feed.read().snapshot.sessionTitle == "Synthetic z")
}

@Test func idleFocusRetainsPreviousSelectionUntilItDisappears() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress", title: "Previously active", startedAt: 1000)
    try fixture.add(id: "z", status: "completed", title: "Newer idle", startedAt: 2000)
    let feed = LocalSessionFeed(home: fixture.root)
    #expect(try await feed.read().snapshot.sessionTitle == "Previously active")
    try fixture.execute("history", "UPDATE thread_turns SET status='completed' WHERE thread_id='a'")
    #expect(try await feed.read().snapshot.sessionTitle == "Previously active")
    try fixture.execute("state", "UPDATE threads SET archived=1 WHERE id='a'")
    #expect(try await feed.read().snapshot.sessionTitle == "Newer idle")
}

@Test func idleFocusActivityTimeTakesPrecedenceOverIdentifier() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "z", status: "completed", title: "Older", startedAt: 1000)
    try fixture.add(id: "a", status: "completed", title: "Newer", startedAt: 2000)
    #expect(try await LocalSessionFeed(home: fixture.root).read().snapshot.sessionTitle == "Newer")
}
