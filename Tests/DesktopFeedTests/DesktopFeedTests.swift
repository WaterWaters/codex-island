import CSQLite
@testable import DesktopFeed
import Foundation
import IslandCore
import Testing

@Test func questionWaitsUntilMatchingAnswer() throws {
    var signals = RolloutSignals()
    try signals.consume(event("function_call", call: "q1", name: "request_user_input"), turnID: "t")
    #expect(signals.needsInput)
    try signals.consume(event("function_call_output", call: "other"), turnID: "t")
    #expect(signals.needsInput)
    try signals.consume(event("function_call_output", call: "q1"), turnID: "t")
    #expect(!signals.needsInput)
}

@Test func pendingQuestionsHaveBoundedCountAndIdentifierBytes() throws {
    var signals = RolloutSignals()
    for index in 0..<1024 {
        try signals.consume(event("function_call", call: "q\(index)", name: "request_user_input"), turnID: "t")
    }
    #expect(throws: FeedError.oversized) {
        try signals.consume(event("function_call", call: "overflow", name: "request_user_input"), turnID: "t")
    }
    try signals.consume(event("function_call_output", call: "q0"), turnID: "t")
    try signals.consume(asyncCall("async"), turnID: "t")
    #expect(throws: FeedError.oversized) {
        try signals.consume(event("function_call", call: String(repeating: "x", count: 513), name: "request_user_input"), turnID: "t")
    }
}

@Test func answeredAsyncQuestionsReleaseCapacityDuringLongTurns() throws {
    var signals = RolloutSignals()
    for index in 0..<1100 {
        let id = "q\(index)"
        try signals.consume(asyncCall(id), turnID: "t")
        try signals.consume(asyncAck(id), turnID: "t")
        #expect(signals.needsInput)
        try signals.consume(questionReply(id), turnID: "t")
        #expect(!signals.needsInput)
    }
}

@Test func foreignTurnAndOrdinaryToolsDoNotRequestInput() throws {
    var signals = RolloutSignals()
    try signals.consume(event("function_call", call: "q", name: "exec_command"), turnID: "t")
    try signals.consume(event("function_call", call: "q", name: "request_user_input", turn: "old"), turnID: "t")
    #expect(!signals.needsInput)
}

@Test func terminalEventClearsQuestion() throws {
    var signals = RolloutSignals()
    try signals.consume(event("function_call", call: "q", name: "functions.request_user_input"), turnID: "t")
    try signals.consume(Data(#"{"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"t"}}"#.utf8), turnID: "t")
    #expect(!signals.needsInput)
}

@Test func activeSessionSurvivesQuietPeriodsAndCompletionDoesNotInventUnread() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    try fixture.add(id: "b", status: "completed")
    try fixture.add(id: "child", status: "inProgress", agent: "/root/worker")
    let feed = LocalSessionFeed(home: fixture.root)
    let first = try await feed.read()
    #expect(first.snapshot.activities == [.running])
    #expect(first.trackedThreads == 2)
    #expect(!first.supportsUnread)
    #expect(try await feed.read().snapshot.activities == [.running])
    try fixture.execute("history", "UPDATE thread_turns SET status='completed' WHERE thread_id='a'")
    #expect(try await feed.read().snapshot.activities.isEmpty)
}

@Test func explicitQuestionAndAnswerAreConsumedIncrementally() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    let feed = LocalSessionFeed(home: fixture.root)
    #expect(try await feed.read().snapshot.activities == [.running])
    try fixture.append(event("function_call", call: "q", name: "request_user_input"), id: "a")
    #expect(try await feed.read().snapshot.activities == [.needsInput])
    try fixture.append(event("function_call_output", call: "q"), id: "a")
    #expect(try await feed.read().snapshot.activities == [.running])
}

@Test func systemSubagentWithoutAChildPathIsExcluded() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "root", status: "inProgress")
    try fixture.add(id: "guardian", status: "inProgress", source: #"{"subagent":{"other":"guardian"}}"#)
    try fixture.execute("state", "UPDATE threads SET agent_path=NULL WHERE id='guardian'")
    let observation = try await LocalSessionFeed(home: fixture.root).read()
    #expect(observation.activeThreads == 1)
    #expect(observation.trackedThreads == 1)
    #expect(observation.snapshot.activities == [.running])
}

@Test func partialRecordIsNotTreatedAsACompletedRead() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    let line = event("function_call", call: "q", name: "request_user_input")
    let mid = line.count / 2
    try fixture.append(Data(line.prefix(mid)), id: "a", newline: false)
    let feed = LocalSessionFeed(home: fixture.root)
    #expect(try await feed.read().snapshot.activities == [.running])
    try fixture.append(Data(line.suffix(line.count - mid)), id: "a")
    #expect(try await feed.read().snapshot.activities == [.needsInput])
}

@Test func newTurnCannotInheritOldQuestion() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    try fixture.append(event("function_call", call: "q", name: "request_user_input"), id: "a")
    let feed = LocalSessionFeed(home: fixture.root)
    #expect(try await feed.read().snapshot.activities == [.needsInput])
    let path = fixture.rollout("a")
    let size = (try FileManager.default.attributesOfItem(atPath: path.path)[.size] as! NSNumber).intValue
    try fixture.execute("history", "INSERT INTO thread_turns VALUES ('a','new','inProgress',2,\(size),NULL,2000)")
    #expect(try await feed.read().snapshot.activities == [.running])
}

@Test func historicalFailuresAreNotReplayed() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "old", status: "failed", endedAt: 1)
    let feed = LocalSessionFeed(home: fixture.root)
    #expect(try await feed.read().snapshot.activities.isEmpty)
    try fixture.add(id: "new", status: "failed", endedAt: Date().timeIntervalSince1970 + 1)
    #expect(try await feed.read().snapshot.activities == [.blocked])
    await feed.reset()
    #expect(try await feed.read().snapshot.sessionID != "")
}

@Test func unknownTurnStatusIsNotIdle() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "futureState")
    await #expect(throws: FeedError.incompatibleSchema) { try await LocalSessionFeed(home: fixture.root).read() }
}

@Test func missingAndIncompatibleDatabasesAreExplicitErrors() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.execute("history", "DROP TABLE thread_turns")
    await #expect(throws: FeedError.incompatibleSchema) { try await LocalSessionFeed(home: fixture.root).read() }
    try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("thread_history_1.sqlite"))
    await #expect(throws: FeedError.missingDatabase) { try await LocalSessionFeed(home: fixture.root).read() }
}

@Test func outsideRolloutCannotBeReadAndDatabaseIsNotChanged() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    try fixture.execute("state", "UPDATE threads SET rollout_path='/etc/passwd'")
    let state = fixture.root.appendingPathComponent("state_5.sqlite")
    let before = try Data(contentsOf: state)
    let observation = try await LocalSessionFeed(home: fixture.root).read()
    #expect(observation.snapshot.activities == [.running])
    #expect(!observation.caughtUp)
    #expect(try Data(contentsOf: state) == before)
}

@Test func malformedEventsBackOffAndRecoverWithoutRestarting() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    try fixture.append(Data("malformed".utf8), id: "a")
    let feed = LocalSessionFeed(home: fixture.root)
    let now = ContinuousClock.now
    let failed = try await feed.read(at: now)
    #expect(!failed.caughtUp)
    #expect(failed.degradedThreads == 1 && failed.retryingThreads == 1)
    #expect(failed.snapshot.activities == [.running])

    // Repair the same source. A read before the deadline must not parse it.
    try Data().write(to: fixture.rollout("a"), options: .atomic)
    try fixture.append(event("function_call", call: "q", name: "request_user_input"), id: "a")
    let deferred = try await feed.read(at: now.advanced(by: .milliseconds(999)))
    #expect(deferred.snapshot.activities == [.running])
    #expect(deferred.retryingThreads == 1)
    let recovered = try await feed.read(at: now.advanced(by: .seconds(1)))
    #expect(recovered.caughtUp)
    #expect(recovered.degradedThreads == 0 && recovered.retryingThreads == 0)
    #expect(recovered.snapshot.activities == [.needsInput])
}

@Test func eventFailureClearsPreviouslyObservedQuestionUntilFullRecovery() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    try fixture.append(event("function_call", call: "q", name: "request_user_input"), id: "a")
    let feed = LocalSessionFeed(home: fixture.root)
    let now = ContinuousClock.now
    #expect(try await feed.read(at: now).snapshot.activities == [.needsInput])
    try fixture.append(Data("broken".utf8), id: "a")
    try fixture.append(event("function_call_output", call: "q"), id: "a")
    let failed = try await feed.read(at: now)
    #expect(failed.snapshot.activities == [.running])
    #expect(!failed.caughtUp && failed.degradedThreads == 1)
    // Replaying the valid question prefix before the same bad record must not
    // resurrect a wait whose answer may be in the unread suffix.
    let retried = try await feed.read(at: now.advanced(by: .seconds(1)))
    #expect(retried.snapshot.activities == [.running])
    #expect(!retried.caughtUp && retried.degradedThreads == 1)
    try Data().write(to: fixture.rollout("a"))
    try fixture.append(event("function_call", call: "q", name: "request_user_input"), id: "a")
    try fixture.append(event("function_call_output", call: "q"), id: "a")
    let recovered = try await feed.read(at: now.advanced(by: .seconds(3)))
    #expect(recovered.caughtUp && recovered.degradedThreads == 0)
    #expect(recovered.snapshot.activities == [.running])
}

@Test func missingEventFileCanRecoverAfterBoundedRetry() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    try FileManager.default.removeItem(at: fixture.rollout("a"))
    let feed = LocalSessionFeed(home: fixture.root)
    let now = ContinuousClock.now
    let missing = try await feed.read(at: now)
    #expect(missing.snapshot.activities == [.running])
    #expect(missing.degradedThreads == 1 && missing.retryingThreads == 1)
    try Data().write(to: fixture.rollout("a"))
    let recovered = try await feed.read(at: now.advanced(by: .seconds(1)))
    #expect(recovered.caughtUp && recovered.degradedThreads == 0)
}

@Test func repeatedFailuresIncreaseBackoffWithThirtySecondCap() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    let broken = Data("broken\n".utf8)
    try broken.write(to: fixture.rollout("a"))
    let feed = LocalSessionFeed(home: fixture.root)
    var now = ContinuousClock.now
    for seconds in [1, 2, 4, 8, 16, 30, 30] {
        let failed = try await feed.read(at: now)
        #expect(failed.retryingThreads == 1)
        try Data().write(to: fixture.rollout("a"))
        try fixture.append(event("function_call", call: "q", name: "request_user_input"), id: "a")
        let before = try await feed.read(at: now.advanced(by: .milliseconds(seconds * 1000 - 1)))
        #expect(before.snapshot.activities == [.running])
        #expect(before.retryingThreads == 1)
        try broken.write(to: fixture.rollout("a"))
        now = now.advanced(by: .seconds(seconds))
    }
    try Data().write(to: fixture.rollout("a"))
    let recovered = try await feed.read(at: now)
    #expect(recovered.caughtUp && recovered.degradedThreads == 0)
}

@Test func brokenSessionDoesNotBlockHealthyQuestionsOrANewTurn() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "bad", status: "inProgress")
    try fixture.add(id: "good", status: "inProgress", title: "Healthy question")
    try fixture.append(Data("broken".utf8), id: "bad")
    try fixture.append(event("function_call", call: "good-q", name: "request_user_input"), id: "good")
    let feed = LocalSessionFeed(home: fixture.root)
    let now = ContinuousClock.now
    let mixed = try await feed.read(at: now)
    #expect(mixed.activeThreads == 2 && mixed.degradedThreads == 1)
    #expect(mixed.snapshot.activities.contains(.needsInput))
    #expect(mixed.snapshot.sessionTitle == "Healthy question")
    let size = try Data(contentsOf: fixture.rollout("bad")).count
    try fixture.execute("history", "UPDATE thread_turns SET turn_id='new',rollout_byte_offset=\(size) WHERE thread_id='bad'")
    try fixture.append(event("function_call", call: "new-q", name: "request_user_input", turn: "new"), id: "bad")
    let nextTurn = try await feed.read(at: now)
    #expect(nextTurn.caughtUp && nextTurn.degradedThreads == 0)
    #expect(nextTurn.snapshot.activities.filter { $0 == .needsInput }.count == 2)
}

@Test func explicitResetClearsEventBackoffImmediately() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    try fixture.append(Data("broken".utf8), id: "a")
    let feed = LocalSessionFeed(home: fixture.root)
    let now = ContinuousClock.now
    let failed = try await feed.read(at: now)
    #expect(failed.degradedThreads == 1)
    try Data().write(to: fixture.rollout("a"))
    try fixture.append(event("function_call", call: "q", name: "request_user_input"), id: "a")
    await feed.reset()
    let reset = try await feed.read(at: now)
    #expect(reset.snapshot.sessionID != failed.snapshot.sessionID)
    #expect(reset.caughtUp && reset.degradedThreads == 0)
    #expect(reset.snapshot.activities == [.needsInput])
}

@Test func completedThreadsReleaseTheirRetryState() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    try fixture.append(Data("broken".utf8), id: "a")
    let feed = LocalSessionFeed(home: fixture.root)
    let now = ContinuousClock.now
    #expect(try await feed.read(at: now).degradedThreads == 1)
    try fixture.execute("history", "UPDATE thread_turns SET status='completed'")
    let completed = try await feed.read(at: now)
    #expect(completed.caughtUp && completed.degradedThreads == 0)
    #expect(completed.snapshot.activities.isEmpty)
    #expect(!completed.supportsUnread)
    try Data().write(to: fixture.rollout("a"))
    try fixture.execute("history", "UPDATE thread_turns SET status='inProgress'")
    #expect(try await feed.read(at: now).caughtUp)
}

@Test func partialReplaysDoNotResetAnExistingFailureBudget() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    let large = try JSONSerialization.data(withJSONObject: ["type": "unused", "padding": String(repeating: "x", count: 180_000)])
    try fixture.append(large, id: "a")
    try fixture.append(large, id: "a")
    try fixture.append(Data("broken".utf8), id: "a")
    let feed = LocalSessionFeed(home: fixture.root)
    let now = ContinuousClock.now
    let partial = try await feed.read(at: now)
    #expect(!partial.caughtUp && partial.degradedThreads == 0)
    #expect(try await feed.read(at: now).retryingThreads == 1)
    let replay = try await feed.read(at: now.advanced(by: .seconds(1)))
    #expect(!replay.caughtUp && replay.degradedThreads == 1)
    #expect(replay.retryingThreads == 0)
    #expect(try await feed.read(at: now.advanced(by: .seconds(1))).retryingThreads == 1)
    try Data().write(to: fixture.rollout("a"))
    #expect(try await feed.read(at: now.advanced(by: .milliseconds(2999))).retryingThreads == 1)
    let recovered = try await feed.read(at: now.advanced(by: .seconds(3)))
    #expect(recovered.caughtUp && recovered.degradedThreads == 0)
}

@Test func changedRolloutPathClearsBackoffWithoutReadingTheOldFile() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    try fixture.append(Data("broken".utf8), id: "a")
    let feed = LocalSessionFeed(home: fixture.root)
    let now = ContinuousClock.now
    #expect(try await feed.read(at: now).retryingThreads == 1)
    let replacement = fixture.rollout("replacement")
    try Data().write(to: replacement)
    try fixture.execute("state", "UPDATE threads SET rollout_path='\(replacement.path.replacingOccurrences(of: "'", with: "''"))'")
    let recovered = try await feed.read(at: now)
    #expect(recovered.caughtUp && recovered.degradedThreads == 0)
}

@Test func titleAndDetailedActivityFollowLatestItemThenRemainIdle() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress", title: "编写状态岛")
    try fixture.setItem(id: "a", type: "reasoning")
    let feed = LocalSessionFeed(home: fixture.root)
    let initial = try await feed.read().snapshot
    #expect(initial.sessionTitle == "编写状态岛")
    #expect(initial.activity == .thinking)
    try fixture.setItem(id: "a", type: "commandExecution", status: "inProgress")
    #expect(try await feed.read().snapshot.activity == .runningCommand)
    try fixture.setItem(id: "a", type: "commandExecution", status: "completed")
    #expect(try await feed.read().snapshot.activity == .ranCommand)
    try fixture.execute("history", "UPDATE thread_turns SET status='completed' WHERE thread_id='a'")
    let idle = try await feed.read().snapshot
    #expect(idle.activities.isEmpty)
    #expect(idle.activity == .idle)
    #expect(idle.sessionTitle == "编写状态岛")
}

@Test func completedTurnSkipsItemScanAndIdleSnapshotRemainsAcceptable() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress", title: "等待下一项任务")
    try fixture.setItem(id: "a", type: "reasoning")
    let feed = LocalSessionFeed(home: fixture.root)
    var gate = SnapshotGate()
    let working = try await feed.read().snapshot
    #expect(try gate.accept(working, now: Date()).state == .running)

    try fixture.execute("history", """
    UPDATE thread_turns SET status='completed';
    ALTER TABLE thread_items RENAME TO stored_items;
    CREATE VIEW thread_items AS SELECT thread_id,turn_id,item_id,item_type,item_json,
      rollout_ordinal,json_extract('not JSON','$') AS updated_at_ordinal,
      created_at_ms,started_at_ms,completed_at_ms FROM stored_items;
    """)
    // This projection deliberately errors if the latest-item sorter runs.
    // Ended turns must only need their turn status, even with item data present.
    let idle = try await feed.read().snapshot
    #expect(try gate.accept(idle, now: Date()).state == .idle)
    #expect(idle.activity == .idle)
    #expect(idle.sessionTitle == working.sessionTitle)
    let restarted = try await LocalSessionFeed(home: fixture.root).read().snapshot
    #expect(try gate.accept(restarted, now: Date()).state == .idle)
}

@Test func needsInputSelectsMatchingTitleAndIdleKeepsThatTitle() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress", title: "需要回答的会话")
    try fixture.add(id: "b", status: "inProgress", title: "较新的会话", startedAt: 2000)
    try fixture.append(event("function_call", call: "q", name: "request_user_input"), id: "a")
    let feed = LocalSessionFeed(home: fixture.root)
    let active = try await feed.read().snapshot
    #expect(active.sessionTitle == "需要回答的会话")
    #expect(active.activity == .needsInput)
    try fixture.execute("history", "UPDATE thread_turns SET status='completed'")
    #expect(try await feed.read().snapshot.sessionTitle == "需要回答的会话")
}

@Test func commandErrorDoesNotStopTheWholeRunningTurn() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    try fixture.setItem(id: "a", type: "commandExecution", status: "failed")
    let value = try await LocalSessionFeed(home: fixture.root).read().snapshot
    #expect(value.activity == .commandFailed)
    #expect(value.activities == [.running])
}

@Test func desktopSessionNameTakesPrecedenceOverInitialPromptTitle() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress", title: "首条提示词")
    try fixture.execute("state", "UPDATE threads SET name='真实会话标题' WHERE id='a'")
    let feed = LocalSessionFeed(home: fixture.root)
    #expect(try await feed.read().snapshot.sessionTitle == "真实会话标题")
    try fixture.execute("state", "UPDATE threads SET name='重命名后的会话' WHERE id='a'")
    #expect(try await feed.read().snapshot.sessionTitle == "重命名后的会话")
}

@Test func asyncAcknowledgementWaitsForTheActualAnswer() throws {
    var signals = RolloutSignals()
    try signals.consume(asyncCall("q"), turnID: "t")
    #expect(!signals.needsInput)
    try signals.consume(asyncAck("q"), turnID: "t")
    #expect(signals.needsInput)
    try signals.consume(questionReply("other"), turnID: "t")
    #expect(signals.needsInput)
    try signals.consume(questionReply("q"), turnID: "t")
    #expect(!signals.needsInput)
}

@Test func partialAsyncRepliesAndSeparateCallsRemainPending() throws {
    var signals = RolloutSignals()
    for id in ["a", "b"] {
        try signals.consume(asyncCall(id, count: 2), turnID: "t")
        try signals.consume(asyncAck(id), turnID: "t")
    }
    for (call, index) in [("a", 0), ("a", 1), ("b", 0)] {
        try signals.consume(questionReply(call, index: index), turnID: "t")
        #expect(signals.needsInput)
    }
    try signals.consume(questionReply("b", index: 1), turnID: "t")
    #expect(!signals.needsInput)
}

@Test func rejectedRequestsAndEarlyRepliesNeverResurrectWaiting() throws {
    var signals = RolloutSignals()
    try signals.consume(asyncCall("early"), turnID: "t")
    try signals.consume(questionReply("early"), turnID: "t")
    try signals.consume(asyncAck("early"), turnID: "t")
    #expect(!signals.needsInput)
    try signals.consume(asyncCall("rejected"), turnID: "t")
    try signals.consume(asyncAck("rejected", accepted: false), turnID: "t")
    #expect(!signals.needsInput)
    try signals.consume(asyncAck("rejected"), turnID: "t")
    #expect(!signals.needsInput)
}

@Test func asyncReplyRequiresStructuredUserEnvelopeAndTerminalClearsIt() throws {
    var signals = RolloutSignals()
    try signals.consume(asyncCall("q"), turnID: "t")
    try signals.consume(asyncAck("q"), turnID: "t")
    try signals.consume(questionReply("q", role: "assistant"), turnID: "t")
    try signals.consume(questionReply("q", prefix: "Example: "), turnID: "t")
    try signals.consume(questionReply("q", turn: "old"), turnID: "t")
    #expect(signals.needsInput)
    try signals.consume(Data(#"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"t"}}"#.utf8), turnID: "t")
    #expect(!signals.needsInput)
    try signals.consume(asyncAck("q"), turnID: "t")
    #expect(!signals.needsInput)
}

@Test func asyncQuestionLifecycleIsReadIncrementallyByTheFeed() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress", title: "等待回答")
    let feed = LocalSessionFeed(home: fixture.root)
    try fixture.append(asyncCall("q"), id: "a")
    try fixture.append(asyncAck("q"), id: "a")
    let waiting = try await feed.read()
    #expect(waiting.caughtUp)
    #expect(waiting.snapshot.activities == [.needsInput])
    #expect(waiting.snapshot.activity == .needsInput)
    #expect(waiting.snapshot.sessionTitle == "等待回答")
    try fixture.append(questionReply("q"), id: "a")
    #expect(try await feed.read().snapshot.activities == [.running])
    try fixture.execute("history", "UPDATE thread_turns SET status='completed'")
    #expect(try await feed.read().snapshot.activity == .idle)
}

private func asyncCall(_ call: String, count: Int = 1) throws -> Data {
    let arguments = String(decoding: try JSONSerialization.data(withJSONObject: ["questions": Array(repeating: ["title": "Not retained"], count: count)]), as: UTF8.self)
    return try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": [
        "type": "function_call", "name": "functions.request_user_input_async", "call_id": call, "arguments": arguments]])
}
private func asyncAck(_ call: String, accepted: Bool = true) throws -> Data {
    let output = String(decoding: try JSONSerialization.data(withJSONObject: ["accepted": accepted]), as: UTF8.self)
    return try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": [
        "type": "function_call_output", "call_id": call, "output": output]])
}
private func questionReply(_ call: String, index: Int = 0, role: String = "user", prefix: String = "", turn: String = "t") throws -> Data {
    let id = String(decoding: try JSONSerialization.data(withJSONObject: ["request_user_input_async", call, index]), as: UTF8.self)
    let body = String(decoding: try JSONSerialization.data(withJSONObject: [["questionItemId": id, "answer": "Not retained"]]), as: UTF8.self)
    let text = prefix + "<send_user_message_question_reply>" + body + "</send_user_message_question_reply>"
    return try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": [
        "type": "message", "role": role, "turn_id": turn, "content": [["type": "input_text", "text": text]]]])
}

private func event(_ type: String, call: String, name: String? = nil, turn: String? = nil) -> Data {
    var payload = ["type": type, "call_id": call]
    payload["name"] = name
    payload["turn_id"] = turn
    return try! JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": payload])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_ISLAND_BENCHMARK"] == "1"))
func syntheticFeedPerformance() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.execute("state", """
    WITH RECURSIVE n(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<1000)
    INSERT INTO threads SELECT 'idle'||i,'unused',0,'/root','vscode','Synthetic',NULL FROM n;
    """)
    try fixture.execute("history", """
    CREATE INDEX turns_by_thread ON thread_turns(thread_id,rollout_ordinal DESC);
    CREATE INDEX items_by_turn ON thread_items(thread_id,turn_id);
    WITH RECURSIVE n(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<1000)
    INSERT INTO thread_turns SELECT 'idle'||i,'t','completed',1,0,2000,1000 FROM n;
    WITH RECURSIVE n(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<100000)
    INSERT INTO thread_items SELECT 'idle'||(1+(i%1000)),'t','item'||i,'reasoning','{}',i,i,1000,NULL,NULL FROM n;
    """)
    let clock = ContinuousClock()
    func measure(_ label: String, active: Int) async throws {
        let feed = LocalSessionFeed(home: fixture.root)
        _ = try await feed.read() // Exclude cold database/cache setup from samples.
        var samples: [Double] = []
        for _ in 0..<30 {
            let start = clock.now
            let result = try await feed.read()
            let elapsed = start.duration(to: clock.now).components
            samples.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            #expect(result.activeThreads == active)
            #expect(result.trackedThreads == 1000 + active)
            #expect(result.caughtUp)
        }
        samples.sort()
        print(String(format: "BENCHMARK %@ samples=30 p50_ms=%.3f p95_ms=%.3f max_ms=%.3f",
                     label, samples[15], samples[28], samples[29]))
    }
    try await measure("1000-idle-100k-history-items", active: 0)
    for index in 0..<32 { try fixture.add(id: "active\(index)", status: "inProgress") }
    try await measure("1000-idle-32-active-tail-caught-up", active: 32)
    var signals = RolloutSignals()
    let start = clock.now
    for index in 0..<10_000 {
        let id = "q\(index)"
        try signals.consume(asyncCall(id), turnID: "t")
        try signals.consume(asyncAck(id), turnID: "t")
        try signals.consume(questionReply(id), turnID: "t")
    }
    #expect(!signals.needsInput)
    let elapsed = start.duration(to: clock.now).components
    print(String(format: "BENCHMARK async-questions=10000 events=30000 elapsed_ms=%.3f",
                 Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15))
}

final class Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("island-feed-test-\(UUID().uuidString)")
    init() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try execute("state", "CREATE TABLE threads(id TEXT PRIMARY KEY,rollout_path TEXT,archived INTEGER,agent_path TEXT,source TEXT,title TEXT,name TEXT)")
        try execute("history", "CREATE TABLE thread_turns(thread_id TEXT,turn_id TEXT,status TEXT,rollout_ordinal INTEGER,rollout_byte_offset INTEGER,completed_at INTEGER,started_at INTEGER)")
        try execute("history", "CREATE TABLE thread_items(thread_id TEXT,turn_id TEXT,item_id TEXT,item_type TEXT,item_json TEXT,rollout_ordinal INTEGER,updated_at_ordinal INTEGER,created_at_ms INTEGER,started_at_ms INTEGER,completed_at_ms INTEGER)")
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func rollout(_ id: String) -> URL { root.appendingPathComponent("sessions/\(id).jsonl") }
    func execute(_ name: String, _ sql: String) throws {
        let path = root.appendingPathComponent(name == "state" ? "state_5.sqlite" : "thread_history_1.sqlite").path
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw FeedError.databaseUnavailable }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw FeedError.databaseUnavailable }
    }
    func add(id: String, status: String, agent: String = "/root", endedAt: Double? = nil, source: String = "vscode",
             title: String? = nil, startedAt: Double = 1000) throws {
        try Data().write(to: rollout(id))
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
        try execute("state", "INSERT INTO threads VALUES (\(quote(id)),\(quote(rollout(id).path)),0,\(quote(agent)),\(quote(source)),\(quote(title ?? "会话 " + id)),NULL)")
        try execute("history", "INSERT INTO thread_turns VALUES (\(quote(id)),'t',\(quote(status)),1,0,\(endedAt.map(String.init(describing:)) ?? "NULL"),\(startedAt))")
    }
    func setItem(id: String, type: String, status: String? = nil) throws {
        var object = ["type": type]
        object["status"] = status
        let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
        try execute("history", "DELETE FROM thread_items WHERE thread_id=\(quote(id))")
        try execute("history", "INSERT INTO thread_items VALUES (\(quote(id)),'t','item',\(quote(type)),\(quote(json)),1,1,3000000,NULL,NULL)")
    }
    func append(_ data: Data, id: String, newline: Bool = true) throws {
        let handle = try FileHandle(forWritingTo: rollout(id))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        if newline { try handle.write(contentsOf: Data([10])) }
    }
}
