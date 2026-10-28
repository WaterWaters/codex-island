import Foundation
import Testing
@testable import ClaudeFeed
import IslandCore

private let sessionID = "00000000-0000-4000-8000-000000000001"

private func makeHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-feed-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("projects/-tmp-project"), withIntermediateDirectories: true)
    return home
}

private func writeRegistry(_ home: URL, pid: Int32 = 4242, status: String = "busy",
                           startedAt: Date = Date(), session: String = sessionID,
                           cwd: String = "/tmp/project") throws {
    let object: [String: Any] = [
        "pid": pid, "sessionId": session, "cwd": cwd,
        "startedAt": startedAt.timeIntervalSince1970 * 1000,
        "status": status, "statusUpdatedAt": startedAt.timeIntervalSince1970 * 1000,
        "name": "Synthetic session", "version": "2.1.309"
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    try data.write(to: home.appendingPathComponent("sessions/\(pid).json"))
}

private func writeTranscript(_ home: URL, lines: [[String: Any]],
                             session: String = sessionID) throws {
    let url = home.appendingPathComponent("projects/-tmp-project/\(session).jsonl")
    let data = try lines.map { line -> String in
        let value = try JSONSerialization.data(withJSONObject: line)
        return String(decoding: value, as: UTF8.self)
    }.joined(separator: "\n") + "\n"
    try Data(data.utf8).write(to: url)
}

private func entry(_ type: String, session: String = sessionID,
                   stop: String? = nil, tool: (id: String, name: String)? = nil,
                   result: String? = nil, apiError: Bool = false,
                   sidechain: Bool = false) -> [String: Any] {
    var object: [String: Any] = [
        "type": type, "sessionId": session,
        "timestamp": "2026-01-01T00:00:00.000Z", "isSidechain": sidechain
    ]
    if type == "assistant" || type == "user" {
        var message: [String: Any] = ["role": type]
        if let stop { message["stop_reason"] = stop }
        var content: [[String: Any]] = []
        if let tool { content.append(["type": "tool_use", "id": tool.id, "name": tool.name]) }
        if let result { content.append(["type": "tool_result", "tool_use_id": result]) }
        if content.isEmpty { content.append(["type": "text", "text": "synthetic"]) }
        message["content"] = content
        object["message"] = message
    }
    if apiError { object["isApiErrorMessage"] = true }
    return object
}

@Test func registryRejectsDeadOrReusedPIDsAndKeepsLiveSessions() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let started = Date(timeIntervalSince1970: 1_700_000_000)
    try writeRegistry(home, pid: 4242, startedAt: started)
    let registry = ClaudeSessionRegistry(liveness: { pid in
        pid == 4242 ? started : nil
    })
    let snapshot = try registry.read(home: home)
    #expect(snapshot.entries.count == 1)
    #expect(snapshot.entries.first?.sessionID == sessionID)
    #expect(snapshot.entries.first?.status == .busy)

    let mismatch = ClaudeSessionRegistry(liveness: { _ in started.addingTimeInterval(60) })
    let rejected = try mismatch.read(home: home)
    #expect(rejected.entries.isEmpty)
    #expect(rejected.skipped == 1)
    #expect(rejected.malformed == 0)
}

@Test func registrySeparatesMalformedFilesFromDeadProcesses() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try Data("{not json".utf8).write(to: home.appendingPathComponent("sessions/bad.json"))
    let snapshot = try ClaudeSessionRegistry(liveness: { _ in Date() }).read(home: home)
    #expect(snapshot.entries.isEmpty)
    #expect(snapshot.malformed == 1)
    #expect(snapshot.skipped == 0)
}

@Test func pendingAskUserQuestionIsNeedsInputAndResolvesOnToolResult() {
    let entry = ClaudeSessionEntry(pid: 1, sessionID: sessionID, cwd: "/tmp/project",
                                   startedAt: Date(), status: .busy, waitingFor: nil, statusUpdatedAt: nil,
                                   updatedAt: nil, name: nil, entrypoint: nil, version: nil)
    var signals = ClaudeTurnSignals()
    signals.apply(ClaudeProjectedEntry(kind: .userPrompt, timestamp: nil, sessionID: sessionID,
                                       stopReason: nil, toolUses: [], toolResults: [],
                                       isSidechain: false, isAPIError: false,
                                       customTitle: nil, agentName: nil))
    signals.apply(ClaudeProjectedEntry(kind: .assistant, timestamp: nil, sessionID: sessionID,
                                       stopReason: "tool_use",
                                       toolUses: [ClaudeToolUse(id: "q1", name: "AskUserQuestion")],
                                       toolResults: [], isSidechain: false, isAPIError: false,
                                       customTitle: nil, agentName: nil))
    #expect(ClaudeSignalReducer.reduce(entry: entry, signals: signals) == .work(.needsInput, .needsInput))

    signals.apply(ClaudeProjectedEntry(kind: .toolResult, timestamp: nil, sessionID: sessionID,
                                       stopReason: nil, toolUses: [], toolResults: ["q1"],
                                       isSidechain: false, isAPIError: false,
                                       customTitle: nil, agentName: nil))
    #expect(ClaudeSignalReducer.reduce(entry: entry, signals: signals) == .work(.running, .thinking))
}

@Test func apiErrorIsBlockedAndTerminalStopIsIdle() {
    let busy = ClaudeSessionEntry(pid: 1, sessionID: sessionID, cwd: "/tmp/project",
                                  startedAt: Date(), status: .busy, waitingFor: nil, statusUpdatedAt: nil,
                                  updatedAt: nil, name: nil, entrypoint: nil, version: nil)
    let idle = ClaudeSessionEntry(pid: 1, sessionID: sessionID, cwd: "/tmp/project",
                                  startedAt: Date(), status: .idle, waitingFor: nil, statusUpdatedAt: nil,
                                  updatedAt: nil, name: nil, entrypoint: nil, version: nil)
    var signals = ClaudeTurnSignals()
    signals.apply(ClaudeProjectedEntry(kind: .assistant, timestamp: nil, sessionID: sessionID,
                                       stopReason: nil, toolUses: [], toolResults: [],
                                       isSidechain: false, isAPIError: true,
                                       customTitle: nil, agentName: nil))
    #expect(ClaudeSignalReducer.reduce(entry: busy, signals: signals) == .work(.blocked, .failed))

    signals.apply(ClaudeProjectedEntry(kind: .assistant, timestamp: nil, sessionID: sessionID,
                                       stopReason: "end_turn", toolUses: [], toolResults: [],
                                       isSidechain: false, isAPIError: false,
                                       customTitle: nil, agentName: nil))
    #expect(ClaudeSignalReducer.reduce(entry: idle, signals: signals) == .work(.idle, .idle))
}

@Test func sidechainEntriesNeverChangeRootState() {
    var signals = ClaudeTurnSignals()
    signals.apply(ClaudeProjectedEntry(kind: .assistant, timestamp: nil, sessionID: sessionID,
                                       stopReason: "tool_use",
                                       toolUses: [ClaudeToolUse(id: "q1", name: "AskUserQuestion")],
                                       toolResults: [], isSidechain: true, isAPIError: false,
                                       customTitle: nil, agentName: nil))
    #expect(signals.pendingTools.isEmpty)
    #expect(signals.lastEntry == .none)
}

@Test func transcriptCursorReadsIncrementallyAndIgnoresPartialLines() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let url = home.appendingPathComponent("projects/-tmp-project/\(sessionID).jsonl")
    let first = try JSONSerialization.data(withJSONObject: entry("user"))
    try first.write(to: url)
    var cursor = ClaudeTranscriptCursor(sessionID: sessionID)
    _ = try cursor.update(url: url, now: .now) // no trailing newline
    #expect(cursor.signals.lastEntry == .none)

    let second = try JSONSerialization.data(withJSONObject: entry("assistant", stop: "end_turn"))
    var combined = Data("\n".utf8)
    combined.append(second)
    combined.append(Data("\n".utf8))
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: combined)
    try handle.close()
    _ = try cursor.update(url: url, now: .now)
    #expect(cursor.signals.lastEntry == .assistant)
    #expect(cursor.signals.lastStopReason == "end_turn")
}

@Test func feedMapsBusyRegistryAndTranscriptToRunningSnapshot() async throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let started = Date()
    try writeRegistry(home, status: "busy", startedAt: started)
    try writeTranscript(home, lines: [
        entry("user"),
        entry("assistant", stop: "tool_use", tool: ("t1", "Bash"))
    ])
    let feed = ClaudeSessionFeed(home: home, liveness: { _ in started })
    let observation = try await feed.read()
    #expect(observation.liveSessions == 1)
    #expect(observation.snapshot.activities == [.running])
    #expect(observation.snapshot.activity == .runningCommand)
    #expect(observation.snapshot.displaySessionTitle == "Synthetic session")
    #expect(observation.caughtUp)
}

@Test func feedWithoutLiveSessionsReportsZero() async throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let feed = ClaudeSessionFeed(home: home, liveness: { _ in nil })
    let observation = try await feed.read()
    #expect(observation.liveSessions == 0)
    #expect(observation.snapshot.activities.isEmpty)
    #expect(observation.caughtUp)
}

@Test func rotationNeverHidesAttentionAndCyclesOnlyRunningSources() {
    let policy = RotationPolicy(dwell: 6, minimumHold: 3, resumeAfterHover: 2)
    let now = Date(timeIntervalSince1970: 1_000)
    let running: [RotationCandidate] = [
        .init(provider: .codex, isConnected: true, state: .running, lastActivityAt: now),
        .init(provider: .claude, isConnected: true, state: .running, lastActivityAt: now)
    ]
    #expect(policy.select(mode: .rotate, current: .codex, candidates: running,
                          lastSwitchAt: now, hovered: false, pausedUntil: nil,
                          now: now.addingTimeInterval(6)) == .claude)
    #expect(policy.select(mode: .rotate, current: .codex, candidates: running,
                          lastSwitchAt: now, hovered: true, pausedUntil: nil,
                          now: now.addingTimeInterval(30)) == .codex)

    let attention: [RotationCandidate] = [
        .init(provider: .codex, isConnected: true, state: .running, lastActivityAt: now),
        .init(provider: .claude, isConnected: true, state: .needsInput, lastActivityAt: now)
    ]
    #expect(policy.select(mode: .rotate, current: .codex, candidates: attention,
                          lastSwitchAt: now, hovered: false, pausedUntil: nil,
                          now: now) == .claude)
    #expect(policy.select(mode: .rotate, current: .claude, candidates: attention,
                          lastSwitchAt: now, hovered: false, pausedUntil: nil,
                          now: now.addingTimeInterval(30)) == .claude)
}

@Test func registryWaitingStatusIsNeedsInputEvenWithoutTranscriptEvidence() {
    let waiting = ClaudeSessionEntry(pid: 1, sessionID: sessionID, cwd: "/tmp/project",
                                     startedAt: Date(), status: .waiting(""),
                                     waitingFor: "input needed",
                                     statusUpdatedAt: nil, updatedAt: nil, name: nil,
                                     entrypoint: nil, version: nil)
    // No transcript signals at all: the registry alone must still surface the wait.
    #expect(ClaudeSignalReducer.reduce(entry: waiting, signals: ClaudeTurnSignals())
            == .work(.needsInput, .needsInput))
    // A permission wait outranks busy work on the same session.
    #expect(waiting.status.isWaiting && !waiting.status.isBusy && !waiting.status.isIdle)
    #expect(waiting.status.waitingReason == "")
}

@Test func registryParsesWaitingStatusAndReason() throws {
    let home = try makeHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let started = Date(timeIntervalSince1970: 1_700_000_000)
    let object: [String: Any] = [
        "pid": 4242, "sessionId": sessionID, "cwd": "/tmp/project",
        "startedAt": started.timeIntervalSince1970 * 1000,
        "status": "waiting", "waitingFor": "sandbox request",
        "statusUpdatedAt": started.timeIntervalSince1970 * 1000,
        "name": "Synthetic session", "version": "2.1.309"
    ]
    try JSONSerialization.data(withJSONObject: object)
        .write(to: home.appendingPathComponent("sessions/4242.json"))
    let snapshot = try ClaudeSessionRegistry(liveness: { _ in started }).read(home: home)
    let entry = try #require(snapshot.entries.first)
    #expect(entry.status.isWaiting)
    #expect(entry.waitingFor == "sandbox request")
}

@Test func settingsDecodeUnknownSourceModeAsCodex() throws {
    let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "sourceMode": "future"])
    let settings = try JSONDecoder().decode(IslandSettings.self, from: data)
    #expect(settings.sourceMode == .codex)
    let missing = try JSONDecoder().decode(IslandSettings.self, from: Data("{}".utf8))
    #expect(missing.sourceMode == .codex)
}
