import CSQLite
import Foundation
import IslandCore

public enum FeedError: String, Error, Sendable {
    case missingDatabase, incompatibleSchema, databaseUnavailable, queryTimedOut, oversized, invalidRollout, invalidConfiguration
}

public struct FeedHealth: Equatable, Sendable {
    public let caughtUp: Bool
    public let degradedThreads: Int
    public let retryingThreads: Int
    public let unresolvedIdentity: Bool

    public init(caughtUp: Bool, degradedThreads: Int = 0, retryingThreads: Int = 0,
                unresolvedIdentity: Bool = false) {
        self.caughtUp = caughtUp
        self.degradedThreads = degradedThreads
        self.retryingThreads = retryingThreads
        self.unresolvedIdentity = unresolvedIdentity
    }
}

public struct FeedObservation: Sendable {
    public let snapshot: ActivitySnapshot
    public let trackedThreads: Int
    public let activeThreads: Int
    public let caughtUp: Bool
    public let degradedThreads: Int
    public let retryingThreads: Int
    public let unresolvedIdentity: Bool
    public let supportsUnread = false
    public var health: FeedHealth {
        FeedHealth(caughtUp: caughtUp, degradedThreads: degradedThreads, retryingThreads: retryingThreads,
                   unresolvedIdentity: unresolvedIdentity)
    }
}

/// Select title and activity metadata only; messages, credentials and tool
/// argument contents never leave the bounded signal parser. Each read reopens SQLite read-only so file
/// replacement and Codex restarts cannot leave a stale database handle alive.
public actor LocalSessionFeed {
    private let configuration: Result<FeedConfiguration, FeedError>
    private var sessionID = UUID().uuidString
    private var startedAt = Date()
    private var cursors: [String: RolloutCursor] = [:]
    private var retries: [String: RolloutRetry] = [:]
    private var focusedID: String?
    private var bindings = HistoryBindingResolver()

    public init(home: URL? = nil) {
        if let home { configuration = .success(FeedConfiguration(home: home)) }
        else {
            do { configuration = .success(try FeedConfiguration()) }
            catch { configuration = .failure(.invalidConfiguration) }
        }
    }

    public func reset() {
        sessionID = UUID().uuidString
        startedAt = Date()
        cursors.removeAll()
        retries.removeAll()
        focusedID = nil
        bindings.reset()
    }

    public func read() throws -> FeedObservation {
        try read(at: ContinuousClock.now)
    }

    // A monotonic instant makes retries deterministic in tests without sleeping
    // or changing the wall clock used for snapshot timestamps and turn history.
    func read(at now: ContinuousClock.Instant) throws -> FeedObservation {
        let home = try configuration.get().home
        let canonical = try StatusDatabase.read(home: home)
        let resolution: BindingResolution
        do {
            let candidates = try StatusDatabase.bindingCandidates(home: home, since: startedAt.timeIntervalSince1970)
            resolution = bindings.resolve(candidates, canonical: canonical, home: home, now: now)
        } catch {
            // A supplemental identity lookup must not erase healthy direct rows.
            resolution = BindingResolution(rows: canonical, files: [:], uncertain: true)
        }
        let rows = resolution.rows
        guard rows.filter({ $0.status == "inProgress" }).count <= 32 else { throw FeedError.oversized }
        var activities: [WorkState] = []
        var activeIDs = Set<String>()
        let cursorIDs = Set(rows.filter { $0.status == "inProgress" }.map(\.id))
        var caughtUp = true
        var unresolvedIdentity = resolution.uncertain
        var candidates: [(row: SessionRow, state: WorkState, activity: SessionActivity)] = []
        for row in rows {
            switch row.status {
            case "inProgress":
                activeIDs.insert(row.id)
                var cursor = cursors[row.id] ?? RolloutCursor()
                if let retry = retries[row.id], !retry.matches(row) {
                    retries.removeValue(forKey: row.id)
                    cursor = RolloutCursor()
                }
                do {
                    if let file = resolution.files[row.id] { try file.requireUnchanged() }
                    if let retry = retries[row.id], now < retry.nextAttempt {
                        caughtUp = false
                        activities.append(.running)
                        candidates.append((row, .running, .from(itemType: row.itemType, status: row.itemStatus)))
                        continue
                    }
                    if let file = resolution.files[row.id] {
                        try cursor.update(row: row, file: file)
                        try file.requireUnchanged()
                    } else { try cursor.update(row: row, home: home) }
                    // A successful partial chunk cannot prove the formerly bad
                    // stream recovered. Retain the failure count until caught up.
                    if cursor.caughtUp { retries.removeValue(forKey: row.id) }
                    caughtUp = caughtUp && cursor.caughtUp
                    if resolution.files[row.id] != nil, cursor.caughtUp, cursor.signals.turnEnded {
                        // A witnessed historical start cannot resurrect a turn
                        // after its matching, fully validated terminal event.
                        activeIDs.remove(row.id)
                        cursors[row.id] = cursor
                        continue
                    }
                    let state: WorkState = cursor.signals.needsInput && cursor.caughtUp ? .needsInput : .running
                    activities.append(state)
                    candidates.append((row, state, state == .needsInput ? .needsInput : .from(itemType: row.itemType, status: row.itemStatus)))
                } catch {
                    if let file = resolution.files[row.id], (try? file.requireUnchanged()) == nil {
                        activeIDs.remove(row.id)
                        cursors.removeValue(forKey: row.id)
                        retries.removeValue(forKey: row.id)
                        unresolvedIdentity = true
                        continue
                    }
                    // The history database proves the turn is active even when
                    // the optional rollout signal stream is unavailable.
                    cursor = RolloutCursor()
                    retries[row.id] = RolloutRetry(row: row, previous: retries[row.id], now: now)
                    caughtUp = false
                    activities.append(.running)
                    candidates.append((row, .running, .from(itemType: row.itemType, status: row.itemStatus)))
                }
                cursors[row.id] = cursor
            case "failed":
                // Do not resurrect historical failures at startup. There is no
                // verified UI unread identity in this compatibility source.
                if let endedAt = row.completedAt, endedAt >= startedAt.timeIntervalSince1970 {
                    if let file = resolution.files[row.id], (try? file.requireUnchanged()) == nil {
                        unresolvedIdentity = true
                        continue
                    }
                    activities.append(.blocked)
                    candidates.append((row, .blocked, .failed))
                }
            case "completed", "interrupted": break
            default: throw FeedError.incompatibleSchema
            }
        }
        cursors = cursors.filter { cursorIDs.contains($0.key) }
        retries = retries.filter { cursorIDs.contains($0.key) }
        let priority: [WorkState: Int] = [.needsInput: 4, .blocked: 3, .ready: 2, .running: 1, .idle: 0]
        let selected = candidates.max {
            let left = priority[$0.state, default: 0], right = priority[$1.state, default: 0]
            if left != right { return left < right }
            if $0.row.activityAt != $1.row.activityAt { return $0.row.activityAt < $1.row.activityAt }
            return $0.row.id < $1.row.id
        }
        let focus = selected?.row ?? rows.first(where: { $0.id == focusedID }) ?? rows.max {
            if $0.activityAt != $1.activityAt { return $0.activityAt < $1.activityAt }
            return $0.id < $1.id
        }
        focusedID = focus?.id
        return FeedObservation(
            snapshot: ActivitySnapshot(source: "local-session-history-v1", sessionID: sessionID,
                                       observedAt: Date(), activities: activities,
                                       sessionTitle: focus?.title, activity: selected?.activity ?? .idle),
            trackedThreads: rows.count, activeThreads: activeIDs.count, caughtUp: caughtUp && !unresolvedIdentity,
            degradedThreads: retries.count, retryingThreads: retries.values.filter { now < $0.nextAttempt }.count,
            unresolvedIdentity: unresolvedIdentity)
    }
}

private struct RolloutRetry {
    let turnID: String
    let path: String
    let startOffset: UInt64
    let failureCount: Int
    let nextAttempt: ContinuousClock.Instant

    init(row: SessionRow, previous: Self?, now: ContinuousClock.Instant) {
        turnID = row.turnID
        path = row.path
        startOffset = row.offset
        failureCount = min((previous?.failureCount ?? 0) + 1, 6)
        let delays = [1, 2, 4, 8, 16, 30]
        nextAttempt = now.advanced(by: .seconds(delays[failureCount - 1]))
    }

    func matches(_ row: SessionRow) -> Bool {
        turnID == row.turnID && path == row.path && startOffset == row.offset
    }
}

struct SessionRow {
    let id: String
    let path: String
    let turnID: String
    let status: String
    let offset: UInt64
    let completedAt: Double?
    let title: String?
    let itemType: String?
    let itemStatus: String?
    let activityAt: Double
}

enum StatusDatabase {
    static func read(home: URL) throws -> [SessionRow] {
        let state = home.appendingPathComponent("state_5.sqlite")
        let history = home.appendingPathComponent("thread_history_1.sqlite")
        guard FileManager.default.fileExists(atPath: state.path),
              FileManager.default.fileExists(atPath: history.path) else { throw FeedError.missingDatabase }
        var db: OpaquePointer?
        guard sqlite3_open_v2(state.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db else {
            if let db { sqlite3_close(db) }
            throw FeedError.databaseUnavailable
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        var attach: OpaquePointer?
        guard sqlite3_prepare_v2(db, "ATTACH DATABASE ? AS history", -1, &attach, nil) == SQLITE_OK else {
            throw FeedError.incompatibleSchema
        }
        defer { sqlite3_finalize(attach) }
        let uri = history.absoluteString + "?mode=ro"
        let bound = uri.withCString { sqlite3_bind_text(attach, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard bound == SQLITE_OK, sqlite3_step(attach) == SQLITE_DONE else { throw FeedError.databaseUnavailable }
        // NULL agent_path is used by older root sessions. Explicit subagents
        // and archived threads never contribute a second activity.
        // The CASE inside the item key is intentional: the LEFT JOIN's status
        // predicate alone does not prevent SQLite evaluating the correlated
        // sorter for completed turns. Idle must never scan old tool items.
        let sql = """
        SELECT t.id, t.rollout_path, h.turn_id, h.status, h.rollout_byte_offset, h.completed_at,
               substr(COALESCE(NULLIF(trim(t.name),''),t.title),1,512), i.item_type,
               CASE WHEN json_valid(i.item_json) THEN json_extract(i.item_json,'$.status') END,
               COALESCE(i.completed_at_ms,i.started_at_ms,i.created_at_ms,h.completed_at*1000,h.started_at*1000,0)
        FROM threads t JOIN history.thread_turns h ON h.thread_id=t.id
        LEFT JOIN history.thread_items i ON h.status='inProgress' AND i.thread_id=h.thread_id AND i.turn_id=h.turn_id
          AND i.item_id=CASE WHEN h.status='inProgress' THEN
            (SELECT item_id FROM history.thread_items z WHERE z.thread_id=h.thread_id AND z.turn_id=h.turn_id
             ORDER BY COALESCE(z.updated_at_ordinal,z.rollout_ordinal) DESC,z.rollout_ordinal DESC LIMIT 1) END
        WHERE t.archived=0 AND (t.agent_path IS NULL OR t.agent_path='/root')
          AND CASE WHEN json_valid(t.source) THEN json_type(t.source,'$.subagent') IS NULL ELSE 1 END
          AND h.turn_id=(SELECT x.turn_id FROM history.thread_turns x
                         WHERE x.thread_id=t.id ORDER BY x.rollout_ordinal DESC LIMIT 1)
        LIMIT 10001
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw FeedError.incompatibleSchema }
        defer { sqlite3_finalize(statement) }
        var deadline = Date().timeIntervalSinceReferenceDate + 0.3
        return try withUnsafeMutablePointer(to: &deadline) { deadline in
            sqlite3_progress_handler(db, 1000, { pointer in
                guard let pointer else { return 1 }
                return Date().timeIntervalSinceReferenceDate > pointer.assumingMemoryBound(to: Double.self).pointee ? 1 : 0
            }, deadline)
            defer { sqlite3_progress_handler(db, 0, nil, nil) }
            var rows: [SessionRow] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                if result == SQLITE_INTERRUPT { throw FeedError.queryTimedOut }
                guard result == SQLITE_ROW else { throw FeedError.databaseUnavailable }
                func text(_ column: Int32) throws -> String {
                    guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
                          let value = sqlite3_column_text(statement, column) else { throw FeedError.incompatibleSchema }
                    return String(cString: value)
                }
                let offset = sqlite3_column_int64(statement, 4)
                guard offset >= 0 else { throw FeedError.incompatibleSchema }
                rows.append(SessionRow(id: try text(0), path: try text(1), turnID: try text(2), status: try text(3),
                                       offset: UInt64(offset), completedAt: sqlite3_column_type(statement, 5) == SQLITE_NULL
                                       ? nil : sqlite3_column_double(statement, 5),
                                       title: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : try text(6),
                                       itemType: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : try text(7),
                                       itemStatus: sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : try text(8),
                                       activityAt: sqlite3_column_double(statement, 9)))
                guard rows.count <= 10_000 else { throw FeedError.oversized }
            }
            return rows
        }
    }
}

extension StatusDatabase {
    /// History namespaces absent from the state catalog are only candidates.
    /// Their rows must never be presented until a file witness binds a root.
    static func bindingCandidates(home: URL, since: Double) throws -> BindingCandidates {
        let state = home.appendingPathComponent("state_5.sqlite")
        let history = home.appendingPathComponent("thread_history_1.sqlite")
        var database: OpaquePointer?
        guard sqlite3_open_v2(state.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db = database else {
            if let database { sqlite3_close(database) }
            throw FeedError.databaseUnavailable
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        var attach: OpaquePointer?
        guard sqlite3_prepare_v2(db, "ATTACH DATABASE ? AS history", -1, &attach, nil) == SQLITE_OK,
              let attach else { throw FeedError.incompatibleSchema }
        defer { sqlite3_finalize(attach) }
        let uri = history.absoluteString + "?mode=ro"
        guard uri.withCString({ sqlite3_bind_text(attach, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }) == SQLITE_OK,
              sqlite3_step(attach) == SQLITE_DONE else { throw FeedError.databaseUnavailable }

        func prepare(_ sql: String) throws -> OpaquePointer {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else { throw FeedError.incompatibleSchema }
            return statement
        }
        func next(_ statement: OpaquePointer) throws -> Bool {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: return true
            case SQLITE_DONE: return false
            case SQLITE_INTERRUPT: throw FeedError.queryTimedOut
            default: throw FeedError.databaseUnavailable
            }
        }
        func text(_ statement: OpaquePointer, _ column: Int32, limit: Int = 16_384) throws -> String {
            let count = Int(sqlite3_column_bytes(statement, column))
            guard sqlite3_column_type(statement, column) == SQLITE_TEXT, count <= limit,
                  let bytes = sqlite3_column_text(statement, column),
                  let value = String(bytes: UnsafeBufferPointer(start: bytes, count: count), encoding: .utf8),
                  !value.utf8.contains(0) else { throw FeedError.incompatibleSchema }
            return value
        }
        var deadline = ContinuousClock.now.advanced(by: .milliseconds(300))
        return try withUnsafeMutablePointer(to: &deadline) { deadline in
            sqlite3_progress_handler(db, 1000, { pointer in
                guard let pointer else { return 1 }
                return ContinuousClock.now > pointer.assumingMemoryBound(to: ContinuousClock.Instant.self).pointee ? 1 : 0
            }, deadline)
            defer { sqlite3_progress_handler(db, 0, nil, nil) }
            let sql = """
            SELECT h.thread_id,h.turn_id,h.status,h.rollout_byte_offset,h.completed_at,i.item_type,
                   CASE WHEN json_valid(i.item_json) THEN json_extract(i.item_json,'$.status') END,
                   COALESCE(i.completed_at_ms,i.started_at_ms,i.created_at_ms,h.completed_at*1000,h.started_at*1000,0)
            FROM history.thread_turns h
            LEFT JOIN threads owner ON owner.id=h.thread_id
            LEFT JOIN history.thread_items i ON h.status='inProgress' AND i.thread_id=h.thread_id AND i.turn_id=h.turn_id
              AND i.item_id=CASE WHEN h.status='inProgress' THEN
                (SELECT item_id FROM history.thread_items z WHERE z.thread_id=h.thread_id AND z.turn_id=h.turn_id
                 ORDER BY COALESCE(z.updated_at_ordinal,z.rollout_ordinal) DESC,z.rollout_ordinal DESC LIMIT 1) END
            WHERE owner.id IS NULL AND (h.status='inProgress' OR (h.status='failed' AND h.completed_at>=?))
              AND h.rollout_ordinal=(SELECT MAX(x.rollout_ordinal) FROM history.thread_turns x WHERE x.thread_id=h.thread_id)
            ORDER BY h.started_at DESC,h.thread_id,h.turn_id
            LIMIT 33
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_double(statement, 1, since) == SQLITE_OK else { throw FeedError.databaseUnavailable }
            var historyRows: [SessionRow] = []
            while try next(statement) {
                let offset = sqlite3_column_int64(statement, 3)
                guard offset >= 0 else { throw FeedError.incompatibleSchema }
                historyRows.append(SessionRow(id: try text(statement, 0, limit: 512), path: "",
                    turnID: try text(statement, 1, limit: 512), status: try text(statement, 2, limit: 32),
                    offset: UInt64(offset), completedAt: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 4),
                    title: nil, itemType: sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : try text(statement, 5, limit: 512),
                    itemStatus: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : try text(statement, 6, limit: 512),
                    activityAt: sqlite3_column_double(statement, 7)))
            }
            guard !historyRows.isEmpty else { return BindingCandidates(roots: [], history: [], exceedsLimit: false) }
            // Recency orders the bounded search only. It never establishes a binding.
            let schema = try prepare("PRAGMA table_info(threads)")
            defer { sqlite3_finalize(schema) }
            var columns = Set<String>()
            while try next(schema) { columns.insert(try text(schema, 1, limit: 512)) }
            let recency = columns.contains("updated_at_ms") ? "COALESCE(t.updated_at_ms,0)"
                : columns.contains("updated_at") ? "COALESCE(t.updated_at,0)*1000" : "0"
            let rootStatement = try prepare("""
            SELECT t.id,t.rollout_path,substr(COALESCE(NULLIF(trim(t.name),''),t.title),1,512),\(recency)
            FROM threads t
            WHERE t.archived=0 AND (t.agent_path IS NULL OR t.agent_path='/root')
              AND CASE WHEN json_valid(t.source) THEN json_type(t.source,'$.subagent') IS NULL ELSE 1 END
            ORDER BY 4 DESC,t.id
            LIMIT 10001
            """)
            defer { sqlite3_finalize(rootStatement) }
            var roots: [BindingRoot] = []
            while try next(rootStatement) {
                roots.append(BindingRoot(id: try text(rootStatement, 0, limit: 512), path: try text(rootStatement, 1),
                    title: sqlite3_column_type(rootStatement, 2) == SQLITE_NULL ? nil : try text(rootStatement, 2, limit: 2048),
                    recency: sqlite3_column_double(rootStatement, 3)))
            }
            return BindingCandidates(roots: Array(roots.prefix(10_000)), history: Array(historyRows.prefix(32)),
                                     exceedsLimit: roots.count > 10_000 || historyRows.count > 32)
        }
    }
}

private struct RolloutCursor {
    private var turnID: String?
    private var fileID: UInt64?
    private var offset: UInt64 = 0
    private var projection = RolloutJSONLProjection()
    private(set) var signals = RolloutSignals()
    private(set) var caughtUp = false

    mutating func update(row: SessionRow, file: RolloutBindingFile) throws {
        if turnID != row.turnID || fileID != UInt64(file.identity.inode) || offset > file.size {
            turnID = row.turnID
            fileID = UInt64(file.identity.inode)
            offset = row.offset
            projection = RolloutJSONLProjection()
            signals = RolloutSignals()
        }
        guard offset <= file.size else { throw FeedError.invalidRollout }
        let data = try file.read(at: offset, maximumBytes: file.remainingBytes)
        offset += UInt64(data.count)
        try projection.consume(data) { line in
            try signals.consumeProjected(line, turnID: row.turnID)
        }
        caughtUp = offset == file.size && !projection.hasPartialRecord
    }

    mutating func update(row: SessionRow, home: URL) throws {
        let path = URL(fileURLWithPath: row.path).resolvingSymlinksInPath()
        let allowed = home.appendingPathComponent("sessions").resolvingSymlinksInPath().path + "/"
        guard path.path.hasPrefix(allowed) else { throw FeedError.invalidRollout }
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        guard let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { throw FeedError.invalidRollout }
        if turnID != row.turnID || fileID != inode || offset > size {
            turnID = row.turnID
            fileID = inode
            offset = row.offset
            projection = RolloutJSONLProjection()
            signals = RolloutSignals()
        }
        guard offset <= size else { throw FeedError.invalidRollout }
        let handle = try FileHandle(forReadingFrom: path)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: RolloutJSONLProjection.readBudget) ?? Data()
        offset += UInt64(data.count)
        try projection.consume(data) { line in
            try signals.consumeProjected(line, turnID: row.turnID)
        }
        caughtUp = offset == size && !projection.hasPartialRecord
    }
}

/// Retain only pending call IDs and question indices. Decode question counts,
/// acceptance flags and structured reply IDs only for the corresponding events;
/// question titles, answers and ordinary tool outputs are never retained.
public struct RolloutSignals: Sendable {
    private static let maximumPendingRequests = 1024
    private static let maximumCallIDBytes = 512
    private var pendingCalls = Set<String>()
    private struct AsyncQuestion: Sendable {
        var remaining: Set<Int>
        var accepted = false
    }
    private var asyncQuestions: [String: AsyncQuestion] = [:]
    private(set) var turnEnded = false
    public var needsInput: Bool {
        !pendingCalls.isEmpty || asyncQuestions.values.contains { $0.accepted && !$0.remaining.isEmpty }
    }
    public init() {}

    public mutating func consume(_ line: Data, turnID: String) throws {
        let projected = try RolloutJSONLProjection.document(line)
        var next = self
        try next.consumeProjected(projected, turnID: turnID)
        self = next
    }

    mutating func consumeProjected(_ line: Data, turnID: String) throws {
        let decoder = JSONDecoder()
        let event = try decoder.decode(Event.self, from: line)
        guard let payload = event.payload else { return }
        if let id = payload.turn_id, id != turnID { return }
        let type = payload.type ?? ""
        if event.type == "event_msg", ["task_started", "task_complete", "turn_complete", "turn_aborted"].contains(type) {
            pendingCalls.removeAll()
            asyncQuestions.removeAll()
            if payload.turn_id == turnID { turnEnded = type != "task_started" }
            return
        }
        guard event.type == "response_item" else { return }
        if type == "message", payload.role == "user" {
            let message = try decoder.decode(Envelope<UserMessage>.self, from: line).payload
            for part in message.content where part.type == "input_text" {
                try part.checkProjection()
                guard let text = part.text else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let start = "<send_user_message_question_reply>", end = "</send_user_message_question_reply>"
                guard trimmed.hasPrefix(start), trimmed.hasSuffix(end) else { continue }
                let body = trimmed.dropFirst(start.count).dropLast(end.count)
                guard let replies = try? decoder.decode([QuestionReply].self, from: Data(body.utf8)) else { continue }
                for reply in replies {
                    guard let id = try? decoder.decode(QuestionID.self, from: Data(reply.questionItemId.utf8)),
                          Self.asyncNames.contains(id.tool), var question = asyncQuestions[id.call] else { continue }
                    question.remaining.remove(id.index)
                    if question.remaining.isEmpty { asyncQuestions.removeValue(forKey: id.call) }
                    else { asyncQuestions[id.call] = question }
                }
            }
            return
        }
        guard let callID = payload.call_id, !callID.isEmpty else { return }
        if type == "function_call" {
            if ["request_user_input", "functions.request_user_input"].contains(payload.name ?? "") {
                try checkCapacity(for: callID)
                pendingCalls.insert(callID)
            } else if Self.asyncNames.contains(payload.name ?? "") {
                try payload.checkProjection("arguments")
                let arguments = try decoder.decode(Envelope<Arguments>.self, from: line).payload.arguments
                if let data = arguments?.data(using: .utf8),
                   let questions = try? decoder.decode(Questions.self, from: data),
                   (1...32).contains(questions.questions.count) {
                    try checkCapacity(for: callID)
                    asyncQuestions[callID] = AsyncQuestion(remaining: Set(questions.questions.indices))
                }
            }
        } else if type == "function_call_output" {
            pendingCalls.remove(callID)
            if var question = asyncQuestions[callID] {
                try payload.checkProjection("output")
                let output = try decoder.decode(Envelope<Output>.self, from: line).payload.output
                if let data = output?.data(using: .utf8),
                   let result = try? decoder.decode(Acceptance.self, from: data), result.accepted {
                    question.accepted = true
                    asyncQuestions[callID] = question
                } else { asyncQuestions.removeValue(forKey: callID) }
            }
        }
    }

    private func checkCapacity(for callID: String) throws {
        guard callID.utf8.count <= Self.maximumCallIDBytes,
              pendingCalls.contains(callID) || asyncQuestions[callID] != nil
                || pendingCalls.count + asyncQuestions.count < Self.maximumPendingRequests else {
            throw FeedError.oversized
        }
    }

    private static let asyncNames = ["request_user_input_async", "functions.request_user_input_async"]
    private struct Envelope<Payload: Decodable>: Decodable { let payload: Payload }
    private struct Arguments: Decodable { let arguments: String? }
    private struct Output: Decodable { let output: String? }
    private struct Questions: Decodable {
        let questions: [Question]
        struct Question: Decodable {}
    }
    private struct Acceptance: Decodable { let accepted: Bool }
    private struct UserMessage: Decodable {
        let content: [Part]
        struct Part: Decodable {
            let type: String?
            let text: String?
            let _island_projection_text_failure: String?
            func checkProjection() throws {
                if let failure = _island_projection_text_failure { throw FeedError(rawValue: failure) ?? .invalidRollout }
            }
        }
    }
    private struct QuestionReply: Decodable { let questionItemId: String }
    private struct QuestionID: Decodable {
        let tool: String
        let call: String
        let index: Int
        init(from decoder: any Decoder) throws {
            var values = try decoder.unkeyedContainer()
            tool = try values.decode(String.self)
            call = try values.decode(String.self)
            index = try values.decode(Int.self)
            guard values.isAtEnd, index >= 0 else { throw FeedError.invalidRollout }
        }
    }
    private struct Event: Decodable {
        let type: String?
        let payload: Payload?
        struct Payload: Decodable {
            let type: String?
            let name: String?
            let call_id: String?
            let turn_id: String?
            let role: String?
            let _island_projection_arguments_failure: String?
            let _island_projection_output_failure: String?
            func checkProjection(_ field: String) throws {
                let failure = field == "arguments" ? _island_projection_arguments_failure : _island_projection_output_failure
                if let failure { throw FeedError(rawValue: failure) ?? .invalidRollout }
            }
        }
    }
}
