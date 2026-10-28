import AppKit

@MainActor
final class CodexLauncher {
    static let bundleID = "com.openai.codex"
    private var lastLaunch = Date.distantPast
    private var inFlight = false

    var runningApplication: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first
    }

    var applicationURL: URL? {
        runningApplication?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID)
    }

    func open() async -> Bool {
        guard !inFlight, Date().timeIntervalSince(lastLaunch) > 0.6 else { return true }
        guard let url = applicationURL else { return false }
        lastLaunch = Date()
        inFlight = true
        defer { inFlight = false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return true
        } catch { return false }
    }
}

/// Claude sessions may come from the desktop app or a terminal. Only the
/// desktop application is opened; a CLI session never guesses a terminal.
@MainActor
final class ClaudeLauncher {
    static let bundleID = "com.anthropic.claudefordesktop"
    private var lastLaunch = Date.distantPast
    private var inFlight = false

    var applicationURL: URL? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID)
    }

    func open() async -> Bool {
        guard !inFlight, Date().timeIntervalSince(lastLaunch) > 0.6 else { return true }
        guard let url = applicationURL else { return false }
        lastLaunch = Date()
        inFlight = true
        defer { inFlight = false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return true
        } catch { return false }
    }
}
