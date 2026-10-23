import DesktopFeed
import Foundation
import Testing

@Test func absentHomeOverrideUsesTheCurrentUsersCodexDirectory() throws {
    let userHome = URL(fileURLWithPath: "/synthetic-user", isDirectory: true)
    let configuration = try FeedConfiguration(environment: [:], userHome: userHome)
    #expect(configuration.home.path == "/synthetic-user/.codex")
    #expect(!configuration.usesHomeOverride)
}

@Test func absoluteHomeOverrideIsSharedAndPreservesSpaces() throws {
    let configuration = try FeedConfiguration(environment: ["CODEX_HOME": "/synthetic user/data/../codex home"])
    #expect(configuration.home.path == "/synthetic user/codex home")
    #expect(configuration.usesHomeOverride)
}

@Test(arguments: ["", " ", "relative/path", "~/.codex", "file:///tmp/codex", "/tmp/invalid\0home"])
func invalidExplicitHomeNeverFallsBack(_ value: String) {
    #expect(throws: FeedError.invalidConfiguration) {
        try FeedConfiguration(environment: ["CODEX_HOME": value])
    }
}

@Test func missingExplicitHomeRemainsMissingRatherThanUsingDefaultData() async throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("island-missing-\(UUID().uuidString)")
    let configuration = try FeedConfiguration(environment: ["CODEX_HOME": missing.path])
    await #expect(throws: FeedError.missingDatabase) {
        try await LocalSessionFeed(home: configuration.home).read()
    }
    #expect(!FileManager.default.fileExists(atPath: missing.path))
}
