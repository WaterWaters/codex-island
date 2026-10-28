import Foundation
import IslandCore

struct ClaudeFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let size: UInt64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
}

struct ClaudeToolUse: Equatable, Sendable {
    let id: String
    let name: String
}

/// Only turn-relevant fields cross the projection boundary. Prompt text,
/// thinking, tool arguments and tool output are never retained.
struct ClaudeProjectedEntry: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case userPrompt, toolResult, assistant, systemAPIError, systemTurnEnd, other
    }

    let kind: Kind
    let timestamp: Date?
    let sessionID: String?
    let stopReason: String?
    let toolUses: [ClaudeToolUse]
    let toolResults: [String]
    let isSidechain: Bool
    let isAPIError: Bool
    let customTitle: String?
    let agentName: String?

    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    static func project(_ data: Data) -> ClaudeProjectedEntry? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let type = object["type"] as? String ?? ""
        let subtype = object["subtype"] as? String
        let timestamp = (object["timestamp"] as? String).flatMap(parseDate)
        let isSidechain = object["isSidechain"] as? Bool ?? false
        let isAPIError = object["isApiErrorMessage"] as? Bool ?? false
        let customTitle = object["customTitle"] as? String
        let agentName = object["agentName"] as? String
        var stopReason: String?
        var toolUses: [ClaudeToolUse] = []
        var toolResults: [String] = []
        if let message = object["message"] as? [String: Any] {
            stopReason = message["stop_reason"] as? String
            if let content = message["content"] as? [[String: Any]] {
                for block in content {
                    switch block["type"] as? String {
                    case "tool_use":
                        if let id = block["id"] as? String, let name = block["name"] as? String {
                            toolUses.append(ClaudeToolUse(id: id, name: name))
                        }
                    case "tool_result":
                        if let id = block["tool_use_id"] as? String {
                            toolResults.append(id)
                        }
                    default:
                        break
                    }
                }
            }
        }
        let kind: Kind
        switch type {
        case "user":
            kind = toolResults.isEmpty ? .userPrompt : .toolResult
        case "assistant":
            kind = .assistant
        case "system":
            if subtype == "api_error" { kind = .systemAPIError }
            else if subtype == "turn_duration" { kind = .systemTurnEnd }
            else { kind = .other }
        default:
            kind = .other
        }
        return ClaudeProjectedEntry(kind: kind, timestamp: timestamp,
                                    sessionID: object["sessionId"] as? String,
                                    stopReason: stopReason, toolUses: toolUses,
                                    toolResults: toolResults, isSidechain: isSidechain,
                                    isAPIError: isAPIError, customTitle: customTitle,
                                    agentName: agentName)
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = try? fractional.parse(value) { return date }
        return try? plain.parse(value)
    }
}

struct ClaudeTurnSignals: Equatable, Sendable {
    enum LastEntry: Equatable, Sendable {
        case none, userPrompt, toolResult, assistant, system
    }

    var pendingTools: [String: String] = [:]
    var lastStopReason: String?
    var lastWasAPIError = false
    var lastEntry: LastEntry = .none
    var turnOpen = false
    var lastActivityAt: Date?
    var customTitle: String?
    var agentName: String?

    var hasPendingTools: Bool { !pendingTools.isEmpty }

    var pendingAttentionTool: String? {
        pendingTools.keys.sorted().compactMap { pendingTools[$0] }
            .first { $0 == "AskUserQuestion" || $0 == "ExitPlanMode" }
    }

    mutating func apply(_ entry: ClaudeProjectedEntry) {
        if entry.isSidechain { return }
        if let title = entry.customTitle, !title.isEmpty { customTitle = title }
        if let name = entry.agentName, !name.isEmpty { agentName = name }
        guard entry.kind != .other else { return }
        if let timestamp = entry.timestamp { lastActivityAt = timestamp }
        switch entry.kind {
        case .userPrompt:
            pendingTools.removeAll()
            lastStopReason = nil
            lastWasAPIError = false
            turnOpen = true
            lastEntry = .userPrompt
        case .toolResult:
            for id in entry.toolResults { pendingTools.removeValue(forKey: id) }
            lastEntry = .toolResult
            turnOpen = true
        case .assistant:
            if entry.isAPIError {
                lastWasAPIError = true
                turnOpen = false
            } else {
                for use in entry.toolUses { pendingTools[use.id] = use.name }
                if let stopReason = entry.stopReason { lastStopReason = stopReason }
                lastWasAPIError = false
                turnOpen = (lastStopReason == "tool_use") || !pendingTools.isEmpty
            }
            lastEntry = .assistant
        case .systemAPIError:
            lastWasAPIError = true
            turnOpen = false
            lastEntry = .system
        case .systemTurnEnd:
            turnOpen = false
            if lastStopReason == nil { lastStopReason = "end_turn" }
            lastEntry = .system
        case .other:
            break
        }
    }
}

enum ClaudeSessionState: Equatable, Sendable {
    case work(WorkState, SessionActivity?)
    case unavailable
}

enum ClaudeSignalReducer {
    static func reduce(entry: ClaudeSessionEntry, signals: ClaudeTurnSignals) -> ClaudeSessionState {
        // The registry is authoritative for a user-facing wait: it is set while a
        // question, dialog, worker or sandbox permission prompt is on screen, and
        // those prompts leave no other local trace.
        if entry.status.isWaiting {
            return .work(.needsInput, .needsInput)
        }
        if signals.pendingAttentionTool != nil {
            return .work(.needsInput, .needsInput)
        }
        if signals.lastWasAPIError {
            return .work(.blocked, .failed)
        }
        switch entry.status {
        case .busy:
            return .work(.running, activity(signals))
        case .idle:
            if signals.hasPendingTools || signals.turnOpen {
                return .work(.running, activity(signals))
            }
            return .work(.idle, .idle)
        case .waiting, .unknown:
            if signals.hasPendingTools || signals.turnOpen {
                return .work(.running, activity(signals))
            }
            return .unavailable
        }
    }

    static func activity(_ signals: ClaudeTurnSignals) -> SessionActivity {
        if let name = signals.pendingTools.keys.sorted().compactMap({ signals.pendingTools[$0] }).first {
            switch name {
            case "Bash": return .runningCommand
            case "Edit", "Write", "MultiEdit", "NotebookEdit": return .editingFiles
            case "Read", "Grep", "Glob", "LS", "WebFetch", "WebSearch": return .searching
            case "Task", "Agent": return .usingTool
            default: return .usingTool
            }
        }
        switch signals.lastEntry {
        case .userPrompt: return .thinking
        case .assistant: return signals.lastStopReason == "tool_use" ? .usingTool : .responding
        case .toolResult: return .thinking
        default: return .idle
        }
    }
}

/// Locates the project transcript. The directory-name encoding is only
/// partially verified, so a derived path must exist and a bounded scan is the
/// fallback. Ambiguous matches stay unresolved instead of guessing.
enum ClaudeTranscriptLocator {
    static func locate(sessionID: String, cwd: String, projects: URL) throws -> URL? {
        guard isValidSessionID(sessionID) else { return nil }
        let root = projects.resolvingSymlinksInPath().standardizedFileURL
        var matches: [URL] = []
        for encoded in encodings(cwd) {
            let url = projects.appendingPathComponent(encoded, isDirectory: true)
                .appendingPathComponent(sessionID + ".jsonl")
            if isRegularFile(url, under: root) { matches.append(url.standardizedFileURL) }
        }
        if matches.isEmpty {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
            for name in names.sorted().prefix(64) where !name.hasPrefix(".") {
                let directory = projects.appendingPathComponent(name, isDirectory: true)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }
                let url = directory.appendingPathComponent(sessionID + ".jsonl")
                if isRegularFile(url, under: root) { matches.append(url.standardizedFileURL) }
            }
        }
        let unique = Array(Set(matches))
        guard unique.count <= 1 else { throw ClaudeFeedError.unresolvedIdentity }
        return unique.first
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

    private static func encodings(_ cwd: String) -> [String] {
        var values = [cwd.replacingOccurrences(of: "/", with: "-")]
        let dotted = cwd.replacingOccurrences(of: ".", with: "-")
        if !values.contains(dotted) { values.append(dotted) }
        return values
    }

    private static func isRegularFile(_ url: URL, under root: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(root.path + "/") else { return false }
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { return false }
        return true
    }
}

struct ClaudeTranscriptCursor: Sendable {
    // One read must cover the whole initial window, otherwise a fresh session
    // reports "not caught up" for many polls and hides confirmed state.
    static let initialWindow: UInt64 = 256 * 1024
    static let readBudget = 256 * 1024
    static let maxLineBytes = 4 * 1024 * 1024

    let sessionID: String
    var offset: UInt64 = 0
    var identity: ClaudeFileIdentity?
    var pending = Data()
    var signals = ClaudeTurnSignals()
    var dropFirstLine = false
    var initialized = false
    var skippingOversizedLine = false
    var skippedOversizedLines = 0

    init(sessionID: String) { self.sessionID = sessionID }

    mutating func update(url: URL, now: ContinuousClock.Instant) throws -> Bool {
        _ = now
        let handle = try Self.open(url)
        defer { try? handle.close() }
        let info = try Self.info(handle)
        let current = ClaudeFileIdentity(
            device: UInt64(info.st_dev), inode: UInt64(info.st_ino), size: UInt64(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec))
        if let identity, identity.device == current.device, identity.inode == current.inode,
           current.size >= offset {
            // Append to the existing cursor.
        } else {
            reset(to: current)
        }
        self.identity = current
        guard current.size > offset else { return !skippingOversizedLine }
        let limit = min(current.size, offset + UInt64(Self.readBudget))
        try handle.seek(toOffset: offset)
        var data = Data()
        let budget = Int(limit - offset)
        while data.count < budget {
            guard let chunk = try handle.read(upToCount: budget - data.count), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        offset += UInt64(data.count)
        try consume(data)
        // A skipped oversized line means the tail cannot be vouched for.
        return offset >= current.size && !skippingOversizedLine && skippedOversizedLines == 0
    }

    private mutating func reset(to identity: ClaudeFileIdentity) {
        offset = identity.size > Self.initialWindow ? identity.size - Self.initialWindow : 0
        pending.removeAll(keepingCapacity: false)
        signals = ClaudeTurnSignals()
        dropFirstLine = offset > 0
        initialized = false
        skippingOversizedLine = false
        skippedOversizedLines = 0
    }

    private mutating func consume(_ data: Data) throws {
        if skippingOversizedLine {
            guard let newline = data.firstIndex(of: 0x0A) else { return }
            skippingOversizedLine = false
            try consume(Data(data[data.index(after: newline)...]))
            return
        }
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            try consumeLine(line)
        }
        if pending.count > Self.maxLineBytes {
            skippedOversizedLines += 1
            skippingOversizedLine = true
            pending.removeAll(keepingCapacity: false)
        }
    }

    private mutating func consumeLine(_ line: Data.SubSequence) throws {
        if dropFirstLine {
            dropFirstLine = false
            initialized = true
            return
        }
        initialized = true
        let trimmed = line.last == 0x0D ? line.dropLast() : line
        guard !trimmed.isEmpty else { return }
        guard let entry = ClaudeProjectedEntry.project(Data(trimmed)) else {
            throw ClaudeFeedError.incompatibleSchema
        }
        if let session = entry.sessionID, session != sessionID {
            throw ClaudeFeedError.unresolvedIdentity
        }
        signals.apply(entry)
    }

    private static func open(_ url: URL) throws -> FileHandle {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ClaudeFeedError.unavailable }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            close(descriptor)
            throw ClaudeFeedError.unavailable
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private static func info(_ handle: FileHandle) throws -> stat {
        var info = stat()
        guard fstat(handle.fileDescriptor, &info) == 0 else { throw ClaudeFeedError.unavailable }
        return info
    }
}
