import Foundation

public enum WorkState: String, Codable, Sendable, CaseIterable {
    case running, needsInput, blocked, ready, idle

    public var title: String {
        switch self {
        case .running: "工作中"
        case .needsInput: "需要你"
        case .blocked: "工作受阻"
        case .ready: "待查看"
        case .idle: "空闲"
        }
    }

    public var symbol: String {
        switch self {
        case .running: "circle.dotted"
        case .needsInput: "exclamationmark"
        case .blocked: "xmark"
        case .ready: "checkmark"
        case .idle: "moon"
        }
    }
}

public enum SessionActivity: String, Codable, Sendable {
    case working, thinking, runningCommand, ranCommand, editingFiles, editedFiles
    case usingTool, usedTool, searching, responding, needsInput, failed, commandFailed, idle

    public var title: String {
        switch self {
        case .working: "工作中"
        case .thinking: "思考中"
        case .runningCommand: "正在运行命令"
        case .ranCommand: "已运行命令"
        case .editingFiles: "正在修改文件"
        case .editedFiles: "已修改文件"
        case .usingTool: "正在使用工具"
        case .usedTool: "已使用工具"
        case .searching: "正在搜索"
        case .responding: "正在回复"
        case .needsInput: "等待你处理"
        case .failed: "执行出错"
        case .commandFailed: "命令执行失败"
        case .idle: "等待新任务"
        }
    }

    public static func from(itemType: String?, status: String?) -> Self {
        if status == "failed" { return itemType == "commandExecution" ? .commandFailed : .failed }
        switch itemType {
        case "reasoning": return .thinking
        case "commandExecution":
            return status == "completed" ? .ranCommand : status == "inProgress" ? .runningCommand : .working
        case "fileChange": return status == "completed" ? .editedFiles : .editingFiles
        case "mcpToolCall", "dynamicToolCall", "collabAgentToolCall", "subAgentActivity":
            return status == "completed" ? .usedTool : .usingTool
        case "webSearch": return .searching
        case "agentMessage": return .responding
        default: return .working
        }
    }
}

/// This is an Island-owned snapshot contract, not a Codex API response.
public struct ActivitySnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let source: String
    public let sessionID: String
    public let observedAt: Date
    public let isComplete: Bool
    public let activities: [WorkState]
    public let sessionTitle: String?
    public let activity: SessionActivity?

    public init(source: String, sessionID: String, observedAt: Date,
                isComplete: Bool = true, activities: [WorkState], schemaVersion: Int = 1,
                sessionTitle: String? = nil, activity: SessionActivity? = nil) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.sessionID = sessionID
        self.observedAt = observedAt
        self.isComplete = isComplete
        self.activities = activities
        self.sessionTitle = sessionTitle
        self.activity = activity
    }

    public var displaySessionTitle: String? {
        guard let sessionTitle else { return nil }
        let title = String(sessionTitle.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ").prefix(160))
        return title.isEmpty ? nil : title
    }

    public func validated(now: Date, maximumAge: TimeInterval = 30) throws -> Self {
        guard schemaVersion == 1 else { throw SnapshotError.unsupportedVersion }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              isComplete, !activities.contains(.idle), activities.count <= 10_000 else {
            throw SnapshotError.incomplete
        }
        guard observedAt.timeIntervalSince(now) <= 5,
              now.timeIntervalSince(observedAt) <= maximumAge else { throw SnapshotError.stale }
        return self
    }
}

public enum SnapshotError: Error, Equatable {
    case unsupportedVersion, incomplete, stale, outOfOrder, retiredSession, oversized
}

public struct ActivitySummary: Equatable, Sendable {
    public let state: WorkState
    public let runningCount: Int
    public let primaryCount: Int

    public static func reduce(_ activities: [WorkState]) -> Self {
        let priority: [WorkState] = [.needsInput, .blocked, .ready, .running]
        let primary = priority.first { activities.contains($0) } ?? .idle
        return Self(state: primary, runningCount: activities.filter { $0 == .running }.count,
                    primaryCount: activities.filter { $0 == primary }.count)
    }

    public var detail: String? {
        if state != .running && runningCount > 0 { return "另有 \(runningCount) 项运行中" }
        if state == .running && runningCount > 1 { return "\(runningCount) 项任务运行中" }
        if state == .ready && primaryCount > 1 { return "\(primaryCount) 项结果待查看" }
        return nil
    }
}

/// A retired source session cannot overwrite a newly accepted session.
public struct SnapshotGate: Sendable {
    private var currentSession: String?
    private var lastObservedAt: Date?
    private var retiredSessions: Set<String> = []

    public init() {}

    public mutating func accept(_ snapshot: ActivitySnapshot, now: Date) throws -> ActivitySummary {
        _ = try snapshot.validated(now: now)
        let identity = snapshot.source + "\u{0}" + snapshot.sessionID
        if currentSession == identity {
            if let lastObservedAt, snapshot.observedAt < lastObservedAt { throw SnapshotError.outOfOrder }
        } else {
            guard !retiredSessions.contains(identity) else { throw SnapshotError.retiredSession }
            // New sessions must also be newer than the last authoritative observation.
            if let lastObservedAt, snapshot.observedAt < lastObservedAt { throw SnapshotError.outOfOrder }
            if let currentSession { retiredSessions.insert(currentSession) }
            currentSession = identity
        }
        lastObservedAt = snapshot.observedAt
        return .reduce(snapshot.activities)
    }
}
