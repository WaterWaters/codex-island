import Foundation
@testable import DesktopFeed
import IslandCore
import Testing

@Suite struct HistoryBindingIntegrationTests {
    @Test func duplicateRootIdentitiesFailClosedWithoutACrash() {
        let root = BindingRoot(id: "duplicate", path: "/synthetic/sessions/root.jsonl", title: nil, recency: 0)
        var resolver = HistoryBindingResolver()
        let value = resolver.resolve(BindingCandidates(roots: [root, root], history: [], exceedsLimit: false),
                                     canonical: [], home: URL(fileURLWithPath: "/synthetic"))
        #expect(value.rows.isEmpty && value.files.isEmpty && value.uncertain)
    }

    @Test func exactFileWitnessRecoversAnUnjoinedCurrentTurn() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try addAliased(fixture, root: "root", namespace: "runtime", canonical: false)
        let feed = LocalSessionFeed(home: fixture.root)
        let value = try await feed.read()
        #expect(value.trackedThreads == 1)
        #expect(value.activeThreads == 1)
        #expect(value.snapshot.activities == [.running])
        #expect(value.caughtUp && !value.unresolvedIdentity)
        #expect(value.snapshot.displaySessionTitle == "Synthetic root")
    }

    @Test func historyItemsStayInTheirVerifiedNamespace() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try addAliased(fixture, root: "root", namespace: "runtime")
        try fixture.setItem(id: "root", type: "wrong-namespace")
        try fixture.execute("history", "INSERT INTO thread_items VALUES ('runtime','alias-turn','item','runtime-tool','{}',2,2,9000,NULL,NULL)")
        let candidates = try StatusDatabase.bindingCandidates(home: fixture.root, since: 0)
        #expect(candidates.history.count == 1)
        #expect(candidates.history.first?.itemType == "runtime-tool")
    }

    @Test func questionRequiresCatchupAndAnswersRemainPaired() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try addAliased(fixture, root: "root", namespace: "runtime")
        try fixture.append(line("response_item", ["type": "function_call_output", "call_id": "ordinary",
            "output": String(repeating: "x", count: 400_000)]), id: "root")
        try fixture.append(line("response_item", ["type": "function_call", "turn_id": "alias-turn",
            "call_id": "question", "name": "request_user_input"]), id: "root")
        let feed = LocalSessionFeed(home: fixture.root)
        var observation = try await feed.read()
        #expect(observation.snapshot.activities == [.running])
        #expect(!observation.caughtUp)
        for _ in 0..<8 where !observation.caughtUp { observation = try await feed.read() }
        #expect(observation.caughtUp)
        #expect(observation.snapshot.activities == [.needsInput])
        try fixture.append(line("response_item", ["type": "function_call_output", "turn_id": "alias-turn",
            "call_id": "unrelated"]), id: "root")
        #expect(try await feed.read().snapshot.activities == [.needsInput])
        try fixture.append(line("response_item", ["type": "function_call_output", "turn_id": "alias-turn",
            "call_id": "question"]), id: "root")
        #expect(try await feed.read().snapshot.activities == [.running])
    }

    @Test func terminalEventDoesNotResurrectAStaleUnjoinedTurn() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try addAliased(fixture, root: "root", namespace: "runtime")
        let feed = LocalSessionFeed(home: fixture.root)
        #expect(try await feed.read().activeThreads == 1)
        try fixture.append(line("event_msg", ["type": "task_complete", "turn_id": "alias-turn"]), id: "root")
        let completed = try await feed.read()
        #expect(completed.snapshot.activities.isEmpty && completed.activeThreads == 0)
        #expect(completed.caughtUp)
        #expect(try await feed.read().activeThreads == 0)
        let offset = try Data(contentsOf: fixture.rollout("root")).count
        try fixture.append(line("event_msg", ["type": "task_started", "turn_id": "next-turn"]), id: "root")
        try fixture.execute("history", "INSERT INTO thread_turns VALUES ('runtime','next-turn','inProgress',78,\(offset),NULL,4000)")
        #expect(try await feed.read().snapshot.activities == [.running])
    }

    @Test func excludedAndUnrelatedNamespacesDoNotBecomeRootActivities() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.add(id: "healthy", status: "inProgress")
        _ = try addAliased(fixture, root: "archived", namespace: "archived-runtime")
        try fixture.execute("state", "UPDATE threads SET archived=1 WHERE id='archived'")
        _ = try addAliased(fixture, root: "child", namespace: "child-runtime")
        try fixture.execute("state", "UPDATE threads SET agent_path='/root/worker' WHERE id='child'")
        _ = try addAliased(fixture, root: "guardian", namespace: "guardian-runtime")
        try fixture.execute("state", "UPDATE threads SET source='{\"subagent\":{\"other\":\"guardian\"}}' WHERE id='guardian'")
        let value = try await LocalSessionFeed(home: fixture.root).read()
        #expect(value.trackedThreads == 1 && value.activeThreads == 1)
        #expect(value.snapshot.activities == [.running])
        #expect(!value.unresolvedIdentity)
    }

    @Test func ambiguousNamespacesPreserveOtherHealthySessions() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.add(id: "healthy", status: "inProgress")
        let offset = try addAliased(fixture, root: "root", namespace: "runtime-a")
        try fixture.execute("history", "INSERT INTO thread_turns VALUES ('runtime-b','alias-turn','inProgress',77,\(offset),NULL,3000)")
        let value = try await LocalSessionFeed(home: fixture.root).read()
        #expect(value.activeThreads == 1)
        #expect(value.snapshot.activities == [.running])
        #expect(value.unresolvedIdentity && !value.caughtUp)
    }

    @Test func copiedTurnInTwoRootFilesCannotBeChosenByRecency() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try addAliased(fixture, root: "root-a", namespace: "runtime")
        _ = try addAliased(fixture, root: "root-b", namespace: "temporary")
        try fixture.execute("history", "DELETE FROM thread_turns WHERE thread_id='temporary'")
        let value = try await LocalSessionFeed(home: fixture.root).read()
        #expect(value.activeThreads == 0 && value.snapshot.activities.isEmpty)
        #expect(value.unresolvedIdentity && !value.caughtUp)
    }

    @Test func conflictingCanonicalTurnIsNotCountedTwiceOrGuessed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try addAliased(fixture, root: "root", namespace: "runtime")
        try fixture.execute("history", "UPDATE thread_turns SET status='inProgress' WHERE thread_id='root'")
        let value = try await LocalSessionFeed(home: fixture.root).read()
        #expect(value.activeThreads == 0 && value.snapshot.activities.isEmpty)
        #expect(value.unresolvedIdentity && !value.caughtUp)
    }

    @Test func replacedProofStaysUnknownUntilItIsRevalidated() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try addAliased(fixture, root: "root", namespace: "runtime")
        let original = try Data(contentsOf: fixture.rollout("root"))
        let feed = LocalSessionFeed(home: fixture.root)
        let now = ContinuousClock.now
        #expect(try await feed.read(at: now).activeThreads == 1)
        try Data("{}\n".utf8).write(to: fixture.rollout("root"), options: .atomic)
        let lost = try await feed.read(at: now.advanced(by: .seconds(1)))
        #expect(lost.activeThreads == 0 && lost.unresolvedIdentity)
        #expect(try await feed.read(at: now.advanced(by: .seconds(2))).unresolvedIdentity)
        try original.write(to: fixture.rollout("root"), options: .atomic)
        let recovered = try await feed.read(at: now.advanced(by: .seconds(32)))
        #expect(recovered.activeThreads == 1 && !recovered.unresolvedIdentity)
        await feed.reset()
        #expect(try await feed.read().activeThreads == 1)
    }

    @Test func discoveryIsBoundedAndMakesProgressAcrossReads() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var targetOffset = 0
        for index in 0..<4 {
            let root = "root\(index)"
            try fixture.add(id: root, status: "completed")
            let header = try line("session_meta", ["id": root]) + Data([10])
            targetOffset = header.count
            let start = try line("event_msg", ["type": "task_started", "turn_id": index == 3 ? "alias-turn" : "other-turn"])
            let body = try line("response_item", ["type": "function_call_output", "call_id": "ordinary",
                "output": String(repeating: "x", count: 300_000)])
            try (header + start + Data([10]) + body + Data([10])).write(to: fixture.rollout(root))
        }
        try fixture.execute("history", "INSERT INTO thread_turns VALUES ('runtime','alias-turn','inProgress',77,\(targetOffset),NULL,3000)")
        let feed = LocalSessionFeed(home: fixture.root)
        var value = try await feed.read()
        #expect(value.activeThreads == 0 && value.unresolvedIdentity)
        for _ in 0..<8 where value.activeThreads == 0 { value = try await feed.read() }
        #expect(value.activeThreads == 1)
    }

    @Test func excessUnknownNamespacesDoNotEraseHealthyDirectActivity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.add(id: "healthy", status: "inProgress")
        for index in 0..<40 {
            try fixture.execute("history", "INSERT INTO thread_turns VALUES ('runtime-\(index)','turn-\(index)','inProgress',1,1,NULL,3000)")
        }
        let value = try await LocalSessionFeed(home: fixture.root).read()
        #expect(value.activeThreads == 1 && value.snapshot.activities == [.running])
        #expect(value.unresolvedIdentity)
    }

    private func addAliased(_ fixture: Fixture, root: String, namespace: String,
                            canonical: Bool = true) throws -> Int {
        try fixture.add(id: root, status: "completed", title: "Synthetic root")
        if !canonical { try fixture.execute("history", "DELETE FROM thread_turns WHERE thread_id=\(quote(root))") }
        let header = try line("session_meta", ["id": root]) + Data([10])
        let start = try line("event_msg", ["type": "task_started", "turn_id": "alias-turn"]) + Data([10])
        try (header + start).write(to: fixture.rollout(root))
        try fixture.execute("history", "INSERT INTO thread_turns VALUES (\(quote(namespace)),'alias-turn','inProgress',77,\(header.count),NULL,3000)")
        return header.count
    }

    private func line(_ type: String, _ payload: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": type, "payload": payload], options: [.sortedKeys])
    }

    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
}
