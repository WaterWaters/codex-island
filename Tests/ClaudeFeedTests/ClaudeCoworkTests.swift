import Foundation
import Testing
@testable import ClaudeFeed
import IslandCore

/// Cowork ("local agent mode") sessions live in the desktop app's own store
/// with a nested Claude home per workspace. Fixtures mirror the observed
/// layout; the fixtures contain only synthetic titles and ids.
private struct CoworkFixture {
    let cliSessionID = UUID().uuidString
    let hostID = UUID().uuidString
    let base: URL
    let workspace: URL
    let cliHome: URL
    let pid: Int32
    let startedAt: Date

    init(base: URL, pid: Int32 = 70438, startedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.base = base
        let profile = base.appendingPathComponent("11111111-2222-3333-4444-555555555555", isDirectory: true)
        workspace = profile.appendingPathComponent(String(hostID.prefix(8)), isDirectory: true)
        cliHome = workspace.appendingPathComponent(String(hostID.prefix(8)), isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
        self.pid = pid
        self.startedAt = startedAt
    }

    var transcriptURL: URL {
        cliHome.appendingPathComponent("projects/session/\(cliSessionID).jsonl")
    }

    func writeHost(archived: Bool = false) throws {
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let object: [String: Any] = [
            "sessionId": "local_\(hostID)",
            "cliSessionId": cliSessionID,
            "title": "Synthetic cowork title",
            "isArchived": archived,
            "lastActivityAt": Int(startedAt.timeIntervalSince1970 * 1000)
        ]
        try JSONSerialization.data(withJSONObject: object)
            .write(to: workspace.appendingPathComponent("local_\(hostID).json"))
    }

    func writeCLIRegistry(status: String = "busy") throws {
        try FileManager.default.createDirectory(at: cliHome.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        let object: [String: Any] = [
            "pid": pid, "sessionId": cliSessionID, "cwd": "/private/var/empty",
            "startedAt": startedAt.timeIntervalSince1970 * 1000,
            "status": status, "statusUpdatedAt": startedAt.timeIntervalSince1970 * 1000,
            "name": "empty-5c", "entrypoint": "local-agent", "version": "2.1.309"
        ]
        try JSONSerialization.data(withJSONObject: object)
            .write(to: cliHome.appendingPathComponent("sessions/\(pid).json"))
    }

    func writeTranscript(lines: [[String: Any]]) throws {
        try FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try lines.map { line -> String in
            String(decoding: try JSONSerialization.data(withJSONObject: line), as: UTF8.self)
        }.joined(separator: "\n") + "\n"
        try Data(data.utf8).write(to: transcriptURL)
    }
}

private func promptEntry(_ session: String) -> [String: Any] {
    ["type": "user", "sessionId": session, "promptSource": "sdk",
     "timestamp": "2026-01-02T00:00:00.000Z",
     "message": ["role": "user", "content": [["type": "text", "text": "synthetic prompt"]]]]
}

private func endTurnEntry(_ session: String) -> [String: Any] {
    ["type": "assistant", "sessionId": session, "timestamp": "2026-01-02T00:00:01.000Z",
     "message": ["role": "assistant",
                 "content": [["type": "text", "text": "done"]],
                 "stop_reason": "end_turn"]]
}

private func toolUseEntry(_ session: String) -> [String: Any] {
    ["type": "assistant", "sessionId": session, "timestamp": "2026-01-02T00:00:01.000Z",
     "message": ["role": "assistant",
                 "content": [["type": "tool_use", "id": "t1", "name": "Bash"]],
                 "stop_reason": "tool_use"]]
}

private func removeTemp(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

@Test func coworkSessionSurfacesStateAndHostTitle() async throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("cowork-primary-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    defer { removeTemp(home) }
    let fixture = CoworkFixture(base: home.appendingPathComponent("cowork-store", isDirectory: true))
    try fixture.writeHost()
    try fixture.writeCLIRegistry(status: "busy")
    try fixture.writeTranscript(lines: [promptEntry(fixture.cliSessionID), toolUseEntry(fixture.cliSessionID)])

    let feed = ClaudeSessionFeed(home: home, coworkDirectory: fixture.base, liveness: { pid in
        pid == fixture.pid ? fixture.startedAt : nil
    })
    let observation = try await feed.read()
    #expect(observation.liveSessions == 1)
    #expect(observation.trackedSessions == 1)
    #expect(observation.unresolvedIdentity == false)
    #expect(observation.snapshot.activities == [.running])
    #expect(observation.snapshot.activity == .runningCommand)
    #expect(observation.snapshot.kind == .cowork)
    #expect(observation.snapshot.sessionTitle == "Synthetic cowork title")
    #expect(observation.version == "2.1.309")
}

@Test func archivedCoworkSessionsAreNotTracked() async throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("cowork-archived-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    defer { removeTemp(home) }
    let fixture = CoworkFixture(base: home.appendingPathComponent("cowork-store", isDirectory: true))
    try fixture.writeHost(archived: true)
    try fixture.writeCLIRegistry(status: "busy")

    let feed = ClaudeSessionFeed(home: home, coworkDirectory: fixture.base, liveness: { _ in nil })
    let observation = try await feed.read()
    #expect(observation.liveSessions == 0)
    #expect(observation.trackedSessions == 0)
    #expect(observation.unresolvedIdentity == false)
}

@Test func workspacesWithoutCLIHomeAreIgnoredSilently() async throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("cowork-nohome-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    defer { removeTemp(home) }
    let fixture = CoworkFixture(base: home.appendingPathComponent("cowork-store", isDirectory: true))
    try fixture.writeHost()

    let feed = ClaudeSessionFeed(home: home, coworkDirectory: fixture.base, liveness: { _ in nil })
    let observation = try await feed.read()
    #expect(observation.liveSessions == 0)
    #expect(observation.unresolvedIdentity == false)
    #expect(observation.degradedSessions == 0)
}

@Test func malformedCoworkHostJSONCountsAsUnresolved() async throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("cowork-badhost-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    defer { removeTemp(home) }
    let fixture = CoworkFixture(base: home.appendingPathComponent("cowork-store", isDirectory: true))
    try fixture.writeHost()
    try fixture.writeCLIRegistry(status: "idle")
    try Data("{ not json".utf8).write(to: fixture.workspace.appendingPathComponent("local_broken.json"))

    let feed = ClaudeSessionFeed(home: home, coworkDirectory: fixture.base, liveness: { _ in nil })
    let observation = try await feed.read()
    #expect(observation.unresolvedIdentity == true)
    #expect(observation.caughtUp == false)
}

@Test func coworkConfigurationStaysOffWithHomeOverride() throws {
    let overridden = try ClaudeFeedConfiguration(
        environment: ["CLAUDE_CONFIG_DIR": "/tmp/claude-home"], userHome: URL(fileURLWithPath: "/Users/synthetic"))
    #expect(overridden.coworkDirectory == nil)

    let defaulted = try ClaudeFeedConfiguration(environment: [:], userHome: URL(fileURLWithPath: "/Users/synthetic"))
    #expect(defaulted.coworkDirectory?.path.hasSuffix("local-agent-mode-sessions") == true)
}

@Test func coworkSessionTracksLiveProcessAndDropsAfterItDies() async throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("cowork-live-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    defer { removeTemp(home) }

    // A real child process exercises the real kernel witness: the same
    // `proc_pidinfo` path the feed uses for live cowork CLIs.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["900"]
    try process.run()
    defer { if process.isRunning { process.terminate() } }
    let processStart: Date
    processStart = ClaudeProcessStart.read(pid: Int32(process.processIdentifier)) ?? .distantPast
    #expect(processStart != .distantPast)
    let fixture = CoworkFixture(base: home.appendingPathComponent("cowork-store", isDirectory: true),
                                pid: Int32(process.processIdentifier), startedAt: processStart)
    try fixture.writeHost()
    try fixture.writeCLIRegistry(status: "busy")
    try fixture.writeTranscript(lines: [promptEntry(fixture.cliSessionID), toolUseEntry(fixture.cliSessionID)])

    // Default liveness is the real `ClaudeProcessStart.read`; no injection.
    let feed = ClaudeSessionFeed(home: home, coworkDirectory: fixture.base)
    let live = try await feed.read()
    #expect(live.liveSessions == 1)
    #expect(live.trackedSessions == 1)
    #expect(live.unresolvedIdentity == false)
    #expect(live.snapshot.activities == [.running])

    process.terminate()
    process.waitUntilExit()
    let dead = try await feed.read()
    #expect(dead.liveSessions == 0)
    #expect(dead.trackedSessions == 0)
    #expect(dead.unresolvedIdentity == false)
}
