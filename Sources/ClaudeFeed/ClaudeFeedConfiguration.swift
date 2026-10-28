import Darwin
import Foundation

public enum ClaudeFeedError: String, Error, Sendable {
    case missingDirectory, unreadableRegistry, incompatibleSchema, oversized
    case unavailable, invalidConfiguration, unresolvedIdentity
}

/// Shared by the app and probe. An explicit invalid override must never
/// silently select another data directory. No path enters diagnostics.
public struct ClaudeFeedConfiguration: Sendable {
    public let home: URL
    public let usesHomeOverride: Bool

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                userHome: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        if let value = environment["CLAUDE_CONFIG_DIR"] {
            guard !value.isEmpty, value.hasPrefix("/"), !value.utf8.contains(0) else {
                throw ClaudeFeedError.invalidConfiguration
            }
            home = URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
            usesHomeOverride = true
        } else {
            home = userHome.appendingPathComponent(".claude", isDirectory: true)
            usesHomeOverride = false
        }
    }

    init(home: URL) {
        self.home = home
        usesHomeOverride = false
    }

    public var sessionsDirectory: URL { home.appendingPathComponent("sessions", isDirectory: true) }
    public var projectsDirectory: URL { home.appendingPathComponent("projects", isDirectory: true) }
}

/// Bounded, no-follow regular-file reads. A FIFO or symlink must not block or
/// escape the selected directory.
enum ClaudeFileReader {
    static func read(url: URL, maxBytes: Int) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ClaudeFeedError.unavailable }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw ClaudeFeedError.unavailable }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw ClaudeFeedError.unavailable }
        guard info.st_size >= 0 else { throw ClaudeFeedError.unavailable }
        guard info.st_size <= maxBytes else { throw ClaudeFeedError.oversized }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: min(65_536, maxBytes))
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count <= 0 { break }
            data.append(buffer, count: count)
            if data.count > maxBytes { throw ClaudeFeedError.oversized }
        }
        return data
    }
}
