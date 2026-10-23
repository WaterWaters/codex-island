import Foundation
import IslandCore
import DesktopFeed
import OSLog
import Darwin

enum SourceReading: Sendable {
    case snapshot(ActivitySnapshot, health: FeedHealth? = nil)
    case unsupported
    case unavailable
}

protocol StatusSource: Sendable {
    func read() async -> SourceReading
    func reset() async
}

extension StatusSource {
    func reset() async {}
}

/// Compatibility source with an explicit local-history scope, not pet parity.
actor DesktopStatusSource: StatusSource {
    private let feed = LocalSessionFeed()
    private let logger = Logger(subsystem: "dev.water.codex-island", category: "StatusSource")
    private var lastFailure: String?
    private var eventsDegraded = false
    func read() async -> SourceReading {
        do {
            let observation = try await feed.read()
            if lastFailure != nil { logger.notice("Local status source recovered") }
            lastFailure = nil
            let degraded = observation.degradedThreads > 0
            if degraded != eventsDegraded {
                if degraded { logger.warning("Local event stream degraded; bounded retries active") }
                else { logger.notice("Local event stream recovered") }
                eventsDegraded = degraded
            }
            return .snapshot(observation.snapshot, health: observation.health)
        } catch {
            // Fixed error identifiers only: never log titles, paths or payloads.
            let reason = (error as? FeedError)?.rawValue ?? "unknownReadFailure"
            if lastFailure != reason { logger.error("Local status read failed: \(reason, privacy: .public)") }
            lastFailure = reason
            switch error as? FeedError {
            case .missingDatabase, .incompatibleSchema: return .unsupported
            default: return .unavailable
            }
        }
    }
    func reset() async {
        await feed.reset()
        eventsDegraded = false
    }
}

/// Explicit integration input. Never selected automatically as a live source.
actor SnapshotFileSource: StatusSource {
    let url: URL
    init(url: URL) { self.url = url }

    func read() -> SourceReading {
        do {
            // A FIFO can block in open(), before a byte limit is useful. Check
            // the opened descriptor so a path replacement cannot bypass this.
            let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { return .unavailable }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            var info = stat()
            guard fstat(descriptor, &info) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  info.st_size >= 0, info.st_size <= 262_144 else { return .unavailable }
            let data = try handle.read(upToCount: 262_145) ?? Data()
            guard data.count <= 262_144 else { throw SnapshotError.oversized }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return .snapshot(try decoder.decode(ActivitySnapshot.self, from: data))
        } catch { return .unavailable }
    }
}

struct DemoStatusSource: StatusSource {
    let state: WorkState
    func read() async -> SourceReading {
        .snapshot(ActivitySnapshot(source: "demo", sessionID: "preview", observedAt: Date(),
                                   activities: state == .idle ? [] : (state == .running ? [.running, .running] : [state, .running]),
                                   sessionTitle: "设计 Codex 浮窗小工具", activity: state == .running ? .runningCommand : nil))
    }
}
