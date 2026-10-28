import Foundation
import IslandCore

public struct ClaudeFeedObservation: Sendable {
    public let snapshot: ActivitySnapshot
    public let liveSessions: Int
    public let trackedSessions: Int
    public let caughtUp: Bool
    public let degradedSessions: Int
    public let retryingSessions: Int
    public let unresolvedIdentity: Bool
    public let version: String?
    public let supportsUnread = false

    public var health: SourceHealth {
        SourceHealth(caughtUp: caughtUp, degradedThreads: degradedSessions,
                     retryingThreads: retryingSessions, unresolvedIdentity: unresolvedIdentity)
    }
}

private struct ClaudeRetry {
    let failureCount: Int
    let nextAttempt: ContinuousClock.Instant

    init(previous: ClaudeRetry?, now: ContinuousClock.Instant) {
        failureCount = min((previous?.failureCount ?? 0) + 1, 6)
        let delays = [1, 2, 4, 8, 16, 30]
        nextAttempt = now.advanced(by: .seconds(delays[failureCount - 1]))
    }
}

/// Read-only Claude Code session feed. Each read re-opens the registry and the
/// selected transcripts; no state is written to `~/.claude`.
public actor ClaudeSessionFeed {
    private let configuration: Result<ClaudeFeedConfiguration, ClaudeFeedError>
    private let registry: ClaudeSessionRegistry
    private var sessionID = UUID().uuidString
    private var cursors: [String: ClaudeTranscriptCursor] = [:]
    private var retries: [String: ClaudeRetry] = [:]

    public init(home: URL? = nil,
                liveness: @escaping ClaudeSessionRegistry.LivenessCheck = ClaudeProcessStart.read) {
        if let home {
            configuration = .success(ClaudeFeedConfiguration(home: home))
        } else {
            do { configuration = .success(try ClaudeFeedConfiguration()) }
            catch { configuration = .failure(.invalidConfiguration) }
        }
        registry = ClaudeSessionRegistry(liveness: liveness)
    }

    public func reset() {
        sessionID = UUID().uuidString
        cursors.removeAll()
        retries.removeAll()
    }

    public func read() throws -> ClaudeFeedObservation {
        try read(at: ContinuousClock.now)
    }

    func read(at now: ContinuousClock.Instant) throws -> ClaudeFeedObservation {
        let config = try configuration.get()
        let registrySnapshot = try registry.read(home: config.home)
        var activities: [WorkState] = []
        var candidates: [(entry: ClaudeSessionEntry, state: WorkState, activity: SessionActivity?, at: Date?)] = []
        var caughtUp = true
        var unresolved = registrySnapshot.malformed > 0
        var degraded = 0
        var retrying = 0
        let liveIDs = Set(registrySnapshot.entries.map(\.sessionID))
        cursors = cursors.filter { liveIDs.contains($0.key) }
        retries = retries.filter { liveIDs.contains($0.key) }

        for entry in registrySnapshot.entries.prefix(32) {
            let transcript: URL?
            do {
                transcript = try ClaudeTranscriptLocator.locate(
                    sessionID: entry.sessionID, cwd: entry.cwd,
                    projects: config.projectsDirectory)
            } catch {
                transcript = nil
                unresolved = true
            }
            guard let transcript else {
                unresolved = true
                continue
            }
            var cursor = cursors[entry.sessionID] ?? ClaudeTranscriptCursor(sessionID: entry.sessionID)
            if let retry = retries[entry.sessionID], now < retry.nextAttempt {
                caughtUp = false
                retrying += 1
                degraded += 1
                if entry.status.isBusy {
                    activities.append(.running)
                    candidates.append((entry, .running, .working,
                                       cursor.signals.lastActivityAt ?? entry.statusUpdatedAt))
                }
                cursors[entry.sessionID] = cursor
                continue
            }
            do {
                let complete = try cursor.update(url: transcript, now: now)
                if complete { retries.removeValue(forKey: entry.sessionID) }
                caughtUp = caughtUp && complete
                switch ClaudeSignalReducer.reduce(entry: entry, signals: cursor.signals) {
                case .work(let state, let activity):
                    if state != .idle { activities.append(state) }
                    // A registry "waiting" carries no transcript evidence, so it
                    // must not be reported as a caught-up question from events.
                    let fromRegistryWait = entry.status.isWaiting
                    if fromRegistryWait && !complete { caughtUp = false }
                    candidates.append((entry, state, activity,
                                       cursor.signals.lastActivityAt ?? entry.statusUpdatedAt))
                case .unavailable:
                    unresolved = true
                }
            } catch {
                retries[entry.sessionID] = ClaudeRetry(previous: retries[entry.sessionID], now: now)
                degraded += 1
                caughtUp = false
                unresolved = true
                if entry.status.isBusy {
                    activities.append(.running)
                    candidates.append((entry, .running, .working,
                                       cursor.signals.lastActivityAt ?? entry.statusUpdatedAt))
                }
            }
            cursors[entry.sessionID] = cursor
        }

        let priority: [WorkState: Int] = [.needsInput: 4, .blocked: 3, .ready: 2, .running: 1, .idle: 0]
        let selected = candidates.max {
            let left = priority[$0.state, default: 0], right = priority[$1.state, default: 0]
            if left != right { return left < right }
            let leftDate = $0.at ?? .distantPast, rightDate = $1.at ?? .distantPast
            if leftDate != rightDate { return leftDate < rightDate }
            return $0.entry.sessionID < $1.entry.sessionID
        }
        let title = selected.flatMap { candidate -> String? in
            let transcript = try? ClaudeTranscriptLocator.locate(
                sessionID: candidate.entry.sessionID, cwd: candidate.entry.cwd,
                projects: config.projectsDirectory)
            return resolveTitle(entry: candidate.entry,
                                signals: cursors[candidate.entry.sessionID]?.signals,
                                transcript: transcript ?? nil)
        }
        let activity = selected?.activity
        return ClaudeFeedObservation(
            snapshot: ActivitySnapshot(
                source: "claude-local-session-v1", sessionID: sessionID, observedAt: Date(),
                activities: activities, sessionTitle: title,
                activity: activity == .idle ? nil : activity),
            liveSessions: registrySnapshot.entries.count,
            trackedSessions: cursors.count,
            caughtUp: caughtUp && !unresolved,
            degradedSessions: degraded,
            retryingSessions: retrying,
            unresolvedIdentity: unresolved,
            version: registrySnapshot.version)
    }

    private func resolveTitle(entry: ClaudeSessionEntry, signals: ClaudeTurnSignals?,
                              transcript: URL?) -> String? {
        if let transcript, let title = readCustomTitle(transcript: transcript, sessionID: entry.sessionID) {
            return title
        }
        if let title = signals?.customTitle, !title.isEmpty { return title }
        if let name = signals?.agentName, !name.isEmpty { return name }
        return entry.name
    }

    private func readCustomTitle(transcript: URL, sessionID: String) -> String? {
        let url = transcript.deletingLastPathComponent()
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("custom-title.json")
        guard let data = try? ClaudeFileReader.read(url: url, maxBytes: 8_192),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = object["customTitle"] as? String,
              !title.isEmpty, title.utf8.count <= 512 else { return nil }
        return title
    }
}
