import Darwin
import Foundation

public enum ClaudeSessionStatus: Equatable, Sendable {
    case busy, idle, waiting(String), unknown(String)

    public var isBusy: Bool { self == .busy }
    public var isIdle: Bool { self == .idle }
    public var isWaiting: Bool { if case .waiting = self { return true }; return false }
    public var waitingReason: String? { if case .waiting(let why) = self { return why }; return nil }
}

public struct ClaudeSessionEntry: Equatable, Sendable {
    public let pid: Int32
    public let sessionID: String
    public let cwd: String
    public let startedAt: Date
    public let status: ClaudeSessionStatus
    public let waitingFor: String?
    public let statusUpdatedAt: Date?
    public let updatedAt: Date?
    public let name: String?
    public let entrypoint: String?
    public let version: String?
}

public struct ClaudeRegistrySnapshot: Sendable {
    public let entries: [ClaudeSessionEntry]
    /// Dead processes and pid mismatches are normal and are not unresolved.
    public let skipped: Int
    /// Files that could not be read or parsed; a live session may be missing.
    public let malformed: Int
    public let version: String?
}

/// Reads the live-session registry. A file whose process is gone, whose
/// start time does not match, or whose JSON is malformed is skipped; it never
/// becomes an active session.
public struct ClaudeSessionRegistry: Sendable {
    public typealias LivenessCheck = @Sendable (Int32) -> Date?

    private let liveness: LivenessCheck

    public init(liveness: @escaping LivenessCheck = ClaudeProcessStart.read) {
        self.liveness = liveness
    }

    public func read(home: URL, maxSessions: Int = 64) throws -> ClaudeRegistrySnapshot {
        let directory = home.appendingPathComponent("sessions", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ClaudeFeedError.missingDirectory
        }
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: directory.path) }
        catch { throw ClaudeFeedError.unreadableRegistry }

        var entries: [ClaudeSessionEntry] = []
        var skipped = 0
        var malformed = 0
        var versionCounts: [String: Int] = [:]
        for name in names.filter({ $0.hasSuffix(".json") }).sorted().prefix(maxSessions) {
            let url = directory.appendingPathComponent(name)
            do {
                let data = try ClaudeFileReader.read(url: url, maxBytes: 65_536)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pid = (object["pid"] as? NSNumber)?.int32Value, pid > 0,
                      let sessionID = validString(object["sessionId"], limit: 128),
                      isValidSessionID(sessionID),
                      let cwd = validString(object["cwd"], limit: 4_096), cwd.hasPrefix("/"),
                      let startedMS = (object["startedAt"] as? NSNumber)?.doubleValue else {
                    malformed += 1
                    continue
                }
                let startedAt = Date(timeIntervalSince1970: startedMS / 1000)
                guard let processStart = liveness(pid),
                      abs(processStart.timeIntervalSince(startedAt)) <= 2 else {
                    skipped += 1
                    continue
                }
                let status: ClaudeSessionStatus
                switch object["status"] as? String {
                case "busy": status = .busy
                case "idle": status = .idle
                case "waiting": status = .waiting("")
                case let value?: status = .unknown(value)
                case nil: status = .unknown("")
                }
                let version = validString(object["version"], limit: 64)
                if let version { versionCounts[version, default: 0] += 1 }
                entries.append(ClaudeSessionEntry(
                    pid: pid,
                    sessionID: sessionID,
                    cwd: cwd,
                    startedAt: startedAt,
                    status: status,
                    waitingFor: validString(object["waitingFor"], limit: 128),
                    statusUpdatedAt: date(milliseconds: object["statusUpdatedAt"]),
                    updatedAt: date(milliseconds: object["updatedAt"]),
                    name: validString(object["name"], limit: 512),
                    entrypoint: validString(object["entrypoint"], limit: 64),
                    version: version))
            } catch {
                malformed += 1
            }
        }
        let version = versionCounts.max { $0.value < $1.value }?.key
        return ClaudeRegistrySnapshot(entries: entries, skipped: skipped,
                                      malformed: malformed, version: version)
    }

    private func date(milliseconds value: Any?) -> Date? {
        guard let number = (value as? NSNumber)?.doubleValue, number > 0 else { return nil }
        return Date(timeIntervalSince1970: number / 1000)
    }

    private func validString(_ value: Any?, limit: Int) -> String? {
        guard let string = value as? String, !string.isEmpty,
              string.utf8.count <= limit, !string.utf8.contains(0) else { return nil }
        return string
    }

    private func isValidSessionID(_ value: String) -> Bool {
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

/// Process start time is the pid-reuse witness. The human-readable `procStart`
/// field is not parsed: it is locale/timezone dependent.
public enum ClaudeProcessStart {
    public static func read(pid: Int32) -> Date? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard result == Int32(size) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
                    + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }
}
