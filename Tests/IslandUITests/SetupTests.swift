import DesktopFeed
import Foundation
import IslandCore
import Testing
@testable import CodexIsland

@MainActor @Test func onboardingCompletionAndSkipPersistIndependentlyOfAppearance() throws {
    for outcome in [OnboardingProgress.Outcome.completed, .skipped] {
        let name = "island-onboarding-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = IslandPreferences(defaults: defaults)
        preferences.values.contentHeight = 102
        preferences.values.neonPrimary = "123456"
        preferences.values.selectedPetID = "synthetic-pet"
        let original = try #require(defaults.data(forKey: IslandPreferences.storageKey))
        let progress = OnboardingProgress(defaults: defaults, permitsAutomaticPresentation: true)
        #expect(progress.shouldPresentAutomatically)
        progress.finish(outcome)
        #expect(defaults.string(forKey: OnboardingProgress.storageKey) == outcome.rawValue)
        #expect(!progress.shouldPresentAutomatically)
        #expect(!OnboardingProgress(defaults: defaults, permitsAutomaticPresentation: true).shouldPresentAutomatically)
        #expect(defaults.data(forKey: IslandPreferences.storageKey) == original)
        preferences.reset()
        #expect(!OnboardingProgress(defaults: defaults, permitsAutomaticPresentation: true).shouldPresentAutomatically)
        #expect(IslandPreferences(defaults: defaults).values.approvalRecognitionEnabled != true)
    }
}

@MainActor @Test func demonstrationAndDiagnosticModesDoNotPermitPersistentChangesOrAutomaticOnboarding() throws {
    #expect(try Options(arguments: [], previewState: nil).permitsPersistentChanges)
    #expect(try Options(arguments: [], previewState: "").permitsPersistentChanges)
    #expect(try Options(arguments: [], previewState: "unknown").permitsPersistentChanges)
    #expect(try !Options(arguments: [], previewState: "running").permitsPersistentChanges)
    #expect(try !Options(arguments: ["--diagnose"], previewState: "running").permitsPersistentChanges)
    for arguments in [["--demo", "running"], ["--diagnose"], ["--demo", "idle", "--diagnose"],
                      ["--render-previews", "/tmp/example.png"], ["--render-gallery", "/tmp/gallery"],
                      ["--status-file", "/tmp/status.json"], ["--help"]] {
        #expect(try !Options(arguments: arguments).permitsPersistentChanges)
    }
    let progress = OnboardingProgress()
    #expect(!progress.shouldPresentAutomatically)
    progress.finish(.completed)
    #expect(!progress.shouldPresentAutomatically)
    // A renderer/demo can change its in-memory appearance without creating a
    // persistent settings object; the next independent model retains defaults.
    let demoPreferences = IslandPreferences()
    demoPreferences.values.contentHeight = 138
    #expect(IslandPreferences().values.contentHeight == IslandSettings().contentHeight)
}

@Test func connectionPresentationSeparatesActionableFailuresAndRecoveryHealth() {
    let states: [(ConnectionState, ConnectionPresentation.Status)] = [
        (.connecting, .checking), (.appNotInstalled, .notInstalled), (.appNotRunning, .notRunning),
        (.missingLocalData, .missingLocalData), (.unsupported, .incompatible), (.unavailable, .temporaryFailure),
        (.connected, .connected)
    ]
    for (connection, expected) in states {
        let presentation = ConnectionPresentation(connection: connection, health: nil)
        #expect(presentation.status == expected)
        #expect(!String(localized: presentation.title).isEmpty)
        #expect(!String(localized: presentation.nextStep).isEmpty)
    }
    #expect(ConnectionPresentation(connection: .connected, health: FeedHealth(caughtUp: false)).status == .synchronizing)
    let degraded = ConnectionPresentation(connection: .connected, health: FeedHealth(caughtUp: false, degradedThreads: 1, retryingThreads: 1))
    #expect(degraded.status == .eventsLimited)
    #expect(ConnectionPresentation(connection: .connected, health: FeedHealth(caughtUp: true)).status == .connected)
    #expect(ConnectionPresentation(connection: .connected, health: nil, isDemo: true).status == .demo)
    #expect(ConnectionPresentation(connection: .connected, health: nil, isExternal: true).status == .external)
    #expect(!ConnectionPresentation(connection: .appNotInstalled, health: nil).offersOpenCodex)
}

@MainActor @Test func diagnosticExportCannotIncludeSessionContentOrUserPaths() throws {
    let model = IslandModel()
    model.isLocalFeed = true
    model.connection = .connected
    model.sessionTitle = "PRIVATE-TITLE /Users/private-user/thread-secret"
    model.activity = .thinking
    model.codexVersion = "/Users/private-user/26.10"
    model.localFeedHealth = FeedHealth(caughtUp: false, degradedThreads: 2, retryingThreads: 1)
    model.sourceFailureReason = .invalidRollout
    let json = try #require(model.privacyDiagnostics.json())
    let data = try #require(json.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["schemaVersion", "islandVersion", "codexVersion", "source", "connection", "reason", "caughtUp", "degradedThreads", "retryingThreads"])
    #expect(object["connection"] as? String == "eventsLimited")
    #expect(object["codexVersion"] as? String == "unknown")
    #expect(object["degradedThreads"] as? Int == 2)
    #expect(object["retryingThreads"] as? Int == 1)
    #expect(!json.contains("PRIVATE"))
    #expect(!json.contains("private-user"))
    #expect(!json.contains("thread-secret"))
    #expect(!json.contains("思考"))
    model.isDemo = true
    #expect(model.privacyDiagnostics.source == "demo")
    #expect(model.privacyDiagnostics.connection == .demo)
}

@Test func diagnosticVersionsAndErrorReasonsUseAClosedVocabulary() {
    #expect(PrivacyDiagnostics.safeVersion("26.1016.61520") == "26.1016.61520")
    for value in ["", "title", "/Users/name", "26.10\nprivate", String(repeating: "1", count: 65)] {
        #expect(PrivacyDiagnostics.safeVersion(value) == "unknown")
    }
    #expect(SourceFailureReason(error: FeedError.invalidConfiguration) == .invalidConfiguration)
    #expect(SourceFailureReason(error: NSError(domain: "/Users/private", code: 42)) == .unknownReadFailure)
}

@Test func desktopSourceMapsMissingIncompatibleAndUnreadableSyntheticDatabases() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("island-source-map-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let absentSource = DesktopStatusSource(feed: LocalSessionFeed(home: home))
    guard case .missingLocalData = await absentSource.read() else {
        Issue.record("Missing local files must offer a data setup step, not report incompatible schema")
        return
    }
    #expect(!FileManager.default.fileExists(atPath: home.path))

    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let state = home.appendingPathComponent("state_5.sqlite")
    let history = home.appendingPathComponent("thread_history_1.sqlite")
    // SQLite treats an empty file as an empty database. It has no compatible
    // tables, so the adapter's real schema query must report unsupported.
    try Data().write(to: state)
    try Data().write(to: history)
    let incompatibleSource = DesktopStatusSource(feed: LocalSessionFeed(home: home))
    guard case .unsupported = await incompatibleSource.read() else {
        Issue.record("A readable database without the expected tables must report incompatibility")
        return
    }
    #expect(try Data(contentsOf: state).isEmpty)
    #expect(try Data(contentsOf: history).isEmpty)

    let corrupt = Data("synthetic corrupt history database".utf8)
    try corrupt.write(to: history)
    let unreadableSource = DesktopStatusSource(feed: LocalSessionFeed(home: home))
    guard case .failure(.databaseUnavailable) = await unreadableSource.read() else {
        Issue.record("A corrupt attached history database must preserve the fixed databaseUnavailable reason")
        return
    }
    #expect(try Data(contentsOf: state).isEmpty)
    #expect(try Data(contentsOf: history) == corrupt)
}
