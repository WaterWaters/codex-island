import Foundation

/// Shared by the app, probe and diagnostics. An explicit invalid override must
/// never silently select another data directory. No path enters diagnostics.
public struct FeedConfiguration: Sendable {
    public let home: URL
    public let usesHomeOverride: Bool

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                userHome: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        if let value = environment["CODEX_HOME"] {
            guard !value.isEmpty, value.hasPrefix("/"), !value.utf8.contains(0) else {
                throw FeedError.invalidConfiguration
            }
            home = URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
            usesHomeOverride = true
        } else {
            home = userHome.appendingPathComponent(".codex", isDirectory: true)
            usesHomeOverride = false
        }
    }

    init(home: URL) {
        self.home = home
        usesHomeOverride = false
    }
}
