import Foundation

/// One indexed desktop cowork ("local agent mode") session. The host JSON is
/// the desktop app's own session store; only allow-listed fields are
/// retained. Prompt payloads, initial messages and system prompts never
/// survive the bounded read: the parsed object is discarded immediately.
public struct ClaudeCoworkSession: Sendable, Equatable {
    /// The nested CLI session UUID: equals the registry and transcript ids.
    public let sessionID: String
    public let title: String
    /// Nested `<host-first-segment>/.claude` config home.
    public let configHome: URL
    /// Host-side last interaction time; ordering hint only.
    public let lastActivityAt: Date?
}

public struct ClaudeCoworkScan: Sendable {
    public let sessions: [ClaudeCoworkSession]
    /// Host files that exist but cannot be read or parsed. A workspace
    /// without a nested CLI home carries no live-state evidence and is
    /// silently omitted, never reported as unavailable.
    public let malformed: Int

    public static let empty = ClaudeCoworkScan(sessions: [], malformed: 0)
}

/// Bounded two-level scan of `…/Claude-3p/local-agent-mode-sessions`:
/// `<profile>/<workspace>/local_<uuid>.json` points at a nested CLI config
/// home at `<workspace>/<first-host-segment>/.claude`, whose layout mirrors
/// the primary `~/.claude` registry and projects. The scan only opens
/// directories and `local_*.json` files; `.key` files, settings and ledger
/// files are never touched.
public enum ClaudeCoworkStore {
    static let maxSessions = 16
    static let maxProfiles = 8
    static let maxWorkspaces = 16
    static let hostMaxBytes = 65_536
    static let titleLimit = 512

    private enum HostOutcome {
        case session(ClaudeCoworkSession)
        case drop
        case malformed
    }

    public static func scan(base: URL?) -> ClaudeCoworkScan {
        guard let base else { return .empty }
        var sessions: [ClaudeCoworkSession] = []
        var malformed = 0
        let ordering: (URL, URL) -> Bool = { $0.path < $1.path }
        for profile in subdirectories(of: base).sorted(by: ordering).prefix(maxProfiles) {
            for workspace in subdirectories(of: profile).sorted(by: ordering).prefix(maxWorkspaces) {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: workspace.path)) ?? []
                let hosts = names
                    .filter { $0.hasPrefix("local_") && $0.hasSuffix(".json") }
                    .sorted()
                for name in hosts {
                    guard sessions.count < maxSessions else {
                        return ClaudeCoworkScan(sessions: sessions, malformed: malformed)
                    }
                    switch parseHost(workspace.appendingPathComponent(name), workspace: workspace) {
                    case .session(let session): sessions.append(session)
                    case .malformed: malformed += 1
                    case .drop: break
                    }
                }
            }
        }
        return ClaudeCoworkScan(sessions: sessions, malformed: malformed)
    }

    private static func parseHost(_ url: URL, workspace: URL) -> HostOutcome {
        guard let data = try? ClaudeFileReader.read(url: url, maxBytes: hostMaxBytes),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed
        }
        guard let hostID = bounded(object["sessionId"], limit: 128), hostID.hasPrefix("local_"),
              let sessionID = bounded(object["cliSessionId"], limit: 128),
              isValidSessionID(sessionID) else {
            return .malformed
        }
        if (object["isArchived"] as? Bool ?? false) { return .drop }
        // Host ids are `local_<36-char-uuid>`; the workspace CLI home lives in
        // the sibling directory named by the id's first 8 hex characters.
        let segment = String(hostID.dropFirst("local_".count).prefix(8))
        let cliHome = workspace.appendingPathComponent(segment, isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
                  atPath: cliHome.appendingPathComponent("sessions", isDirectory: true).path,
                  isDirectory: &isDirectory),
              isDirectory.boolValue else {
            // No nested home: the CLI never started in this workspace, so
            // there is no live state to claim.
            return .drop
        }
        return .session(ClaudeCoworkSession(
            sessionID: sessionID,
            title: bounded(object["title"], limit: titleLimit) ?? "",
            configHome: cliHome,
            lastActivityAt: date(milliseconds: object["lastActivityAt"])))
    }

    private static func subdirectories(of url: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.compactMap { name in
            let child = url.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: child.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            return child
        }
    }

    private static func bounded(_ value: Any?, limit: Int) -> String? {
        guard let string = value as? String, !string.isEmpty,
              string.utf8.count <= limit, !string.utf8.contains(0) else { return nil }
        return string
    }

    private static func date(milliseconds value: Any?) -> Date? {
        guard let number = (value as? NSNumber)?.doubleValue, number > 0 else { return nil }
        return Date(timeIntervalSince1970: number / 1000)
    }

    static func isValidSessionID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 36 else { return false }
        for (index, byte) in bytes.enumerated() {
            if [8, 13, 18, 23].contains(index) {
                guard byte == 45 else { return false }
            } else {
                let isHex = (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
                guard isHex else { return false }
            }
        }
        return true
    }
}
