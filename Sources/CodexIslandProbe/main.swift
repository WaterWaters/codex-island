import ClaudeFeed
import DesktopFeed
import Foundation

@main
enum FeedProbe {
    private struct Result {
        let value: Any
        let failed: Bool
    }

    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        var source = "codex"
        var watch = 1
        if let index = args.firstIndex(of: "--source") {
            guard index + 1 < args.count, ["codex", "claude", "all"].contains(args[index + 1]) else { exit(2) }
            source = args[index + 1]
            args.removeSubrange(index...(index + 1))
        }
        if let index = args.firstIndex(of: "--watch") {
            guard index + 1 < args.count, let count = Int(args[index + 1]), 1...600 ~= count else { exit(2) }
            watch = count
            args.removeSubrange(index...(index + 1))
        }
        guard args.isEmpty else {
            print("Usage: CodexIslandProbe [--source codex|claude|all] [--watch 1...600]")
            exit(2)
        }
        let codex = LocalSessionFeed()
        let claude = ClaudeSessionFeed()
        var failed = false
        for iteration in 0..<watch {
            var output: [String: Any] = [:]
            if source == "codex" || source == "all" {
                let result = await readCodex(codex)
                output["codex"] = result.value
                failed = failed || result.failed
            }
            if source == "claude" || source == "all" {
                let result = await readClaude(claude)
                output["claude"] = result.value
                failed = failed || result.failed
            }
            let payload: Any = source == "all" ? output : (output[source] ?? [:])
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
            if iteration + 1 < watch { try? await Task.sleep(for: .seconds(1)) }
        }
        if failed { exit(1) }
    }

    /// Failures are fixed identifier objects; no path, title or payload is printed.
    private static func readCodex(_ feed: LocalSessionFeed) async -> Result {
        do {
            let observation = try await feed.read()
            let states = observation.snapshot.activities.reduce(into: [String: Int]()) { $0[$1.rawValue, default: 0] += 1 }
            return Result(value: ["source": observation.snapshot.source, "trackedThreads": observation.trackedThreads,
                "activeThreads": observation.activeThreads, "caughtUp": observation.caughtUp,
                "degradedThreads": observation.degradedThreads, "retryingThreads": observation.retryingThreads,
                "unresolvedIdentity": observation.unresolvedIdentity,
                "supportsUnread": observation.supportsUnread, "petParityVerified": false, "states": states,
                "activity": observation.snapshot.activity?.rawValue ?? "unknown",
                "hasSessionTitle": observation.snapshot.displaySessionTitle != nil], failed: false)
        } catch {
            let reason = (error as? FeedError)?.rawValue ?? "unavailable"
            return Result(value: ["error": reason, "petParityVerified": false], failed: true)
        }
    }

    private static func readClaude(_ feed: ClaudeSessionFeed) async -> Result {
        do {
            let observation = try await feed.read()
            let states = observation.snapshot.activities.reduce(into: [String: Int]()) { $0[$1.rawValue, default: 0] += 1 }
            return Result(value: ["source": observation.snapshot.source,
                "liveSessions": observation.liveSessions, "trackedSessions": observation.trackedSessions,
                "caughtUp": observation.caughtUp, "degradedSessions": observation.degradedSessions,
                "retryingSessions": observation.retryingSessions,
                "unresolvedIdentity": observation.unresolvedIdentity,
                "supportsUnread": observation.supportsUnread,
                "version": observation.version ?? "unknown",
                "states": states,
                "activity": observation.snapshot.activity?.rawValue ?? "unknown",
                "hasSessionTitle": observation.snapshot.displaySessionTitle != nil], failed: false)
        } catch {
            let reason = (error as? ClaudeFeedError)?.rawValue ?? "unavailable"
            return Result(value: ["error": reason], failed: true)
        }
    }
}
