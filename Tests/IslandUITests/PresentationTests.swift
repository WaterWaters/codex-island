import Testing
import DesktopFeed
import Foundation
import IslandCore
import Darwin
import CoreGraphics
import ImageIO
@testable import CodexIsland

@Test func externalSnapshotRejectsSpecialFilesWithoutBlocking() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("island-fifo-\(UUID().uuidString)")
    #expect(mkfifo(url.path, 0o600) == 0)
    defer { try? FileManager.default.removeItem(at: url) }
    guard case .unavailable = await SnapshotFileSource(url: url).read() else {
        Issue.record("A named pipe must be rejected without waiting for a writer")
        return
    }
    guard case .unavailable = await SnapshotFileSource(url: url.deletingLastPathComponent()).read() else {
        Issue.record("A directory is not a snapshot file")
        return
    }
}

@Test func externalSnapshotReadsRegularFilesAndRejectsOversizedFiles() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("island-snapshot-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let snapshot = ActivitySnapshot(source: "fixture", sessionID: "test", observedAt: Date(), activities: [.running])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(snapshot).write(to: url, options: .atomic)
    guard case .snapshot(let result, let health, _) = await SnapshotFileSource(url: url).read() else {
        Issue.record("A valid regular snapshot file must remain readable")
        return
    }
    #expect(result.activities == [.running])
    #expect(health == nil)
    try Data(repeating: 32, count: 262_145).write(to: url, options: .atomic)
    guard case .unavailable = await SnapshotFileSource(url: url).read() else {
        Issue.record("An oversized file must be rejected")
        return
    }
}

@MainActor @Test func incompleteLocalEventsRemainWorkingWithVisibleHealth() {
    let previousLanguage = L10n.shared.language
    L10n.shared.configure(language: .zhHans)
    defer { L10n.shared.configure(language: previousLanguage) }
    let model = IslandModel()
    model.isLocalFeed = true
    model.connection = .connected
    model.summary = .reduce([.running])
    model.activity = .thinking
    model.localFeedHealth = SourceHealth(caughtUp: false)
    #expect(model.displayDetail == "思考中 · 同步中")
    model.localFeedHealth = SourceHealth(caughtUp: false, degradedThreads: 1, retryingThreads: 1)
    #expect(model.displayDetail == "思考中 · 同步受限")
    #expect(model.accessibilityDescription.contains("同步受限"))
    #expect(model.state == .running)
    model.localFeedHealth = SourceHealth(caughtUp: true)
    #expect(model.displayDetail == "思考中")
    model.connection = .unavailable
    #expect(model.displayDetail == "状态暂不可用")
}

@MainActor @Test func idleStaysVisibleUntilCodexExits() {
    let previousLanguage = L10n.shared.language
    L10n.shared.configure(language: .zhHans)
    defer { L10n.shared.configure(language: previousLanguage) }
    let model = IslandModel()
    model.connection = .connected
    model.sessionTitle = "当前会话"
    #expect(model.shouldShow)
    #expect(model.title == "当前会话")
    #expect(model.detail == "等待新任务")
    model.connection = .appNotRunning
    #expect(!model.shouldShow)
}

@MainActor @Test func visibilityAndAnimationPreferencesPersistAndCanBeReset() throws {
    let name = "island-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = IslandPreferences(defaults: defaults)
    let model = IslandModel(preferences: preferences)
    model.connection = .connected
    preferences.values.isVisible = false
    preferences.values.animationsEnabled = false
    preferences.values.contentHeight = 110
    #expect(!model.shouldShow)
    #expect(model.motionPaused)
    let restored = IslandPreferences(defaults: defaults)
    #expect(restored.values.contentHeight == 110)
    #expect(!restored.values.isVisible)
    preferences.reset()
    #expect(model.shouldShow)
    #expect(!model.motionPaused)
    #expect(IslandPreferences(defaults: defaults).values.contentHeight == 72)
}

@MainActor @Test func titleAndActivityRemainSeparateAndCommandFailurePulsesRed() {
    let previousLanguage = L10n.shared.language
    L10n.shared.configure(language: .zhHans)
    defer { L10n.shared.configure(language: previousLanguage) }
    let model = IslandModel()
    model.connection = .connected
    model.sessionTitle = "编写浮窗"
    model.summary = .reduce([.running])
    model.activity = .runningCommand
    #expect(model.title == "编写浮窗")
    #expect(model.detail == "正在运行命令")
    model.activity = .commandFailed
    #expect(model.detail == "命令执行失败")
    #expect(model.effectState == .blocked)
    #expect(model.summary.state == .running)
}

@MainActor @Test func petMotionTracksWorkingWaitingErrorAndIdle() {
    let previousLanguage = L10n.shared.language
    L10n.shared.configure(language: .zhHans)
    defer { L10n.shared.configure(language: previousLanguage) }
    let model = IslandModel()
    model.connection = .connected
    model.summary = .reduce([.running])
    model.activity = .thinking
    #expect(model.petMotion == .running)
    model.summary = .reduce([.needsInput, .running])
    #expect(model.petMotion == .waiting)
    model.summary = .reduce([.running])
    model.activity = .commandFailed
    #expect(model.petMotion == .failed)
    #expect(model.summary.state == .running)
    model.activity = .idle
    model.summary = .reduce([])
    #expect(model.petMotion == .idle)
    #expect(model.shouldShow)
    model.connection = .unavailable
    #expect(model.petMotion == .idle)
    #expect(model.displayDetail == "状态暂不可用")
}

@MainActor @Test func demoAndExternalSourcesStayVisibleInStatusText() {
    let previousLanguage = L10n.shared.language
    L10n.shared.configure(language: .zhHans)
    defer { L10n.shared.configure(language: previousLanguage) }
    let model = IslandModel()
    model.connection = .connected
    model.summary = .reduce([.running])
    model.activity = .runningCommand
    model.isDemo = true
    #expect(model.displayDetail == "演示 · 正在运行命令")
    model.isDemo = false
    model.isExternalFeed = true
    #expect(model.displayDetail == "外部 · 正在运行命令")
    model.isExternalFeed = false
    model.isLocalFeed = true
    #expect(model.displayDetail == "正在运行命令")
}

@MainActor @Test func syntheticAtlasHasTransparentDistinctAnimationFrames() throws {
    // Generate anonymous geometric test pixels; never load a personal asset.
    let context = try #require(CGContext(data: nil, width: 1536, height: 2288, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.clear(CGRect(x: 0, y: 0, width: 1536, height: 2288))
    for row in 0..<11 {
        for column in 0..<8 {
            context.setFillColor(CGColor(red: CGFloat(column + 1) / 8, green: 0.3, blue: 0.6, alpha: 1))
            context.fill(CGRect(x: column * 192 + 40, y: row * 208 + 40, width: 80, height: 100))
        }
    }
    let bytes = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    let atlas = try #require(PetAtlas(data: bytes as Data))
    for motion in PetMotion.allCases {
        let first = try #require(atlas.frame(motion: motion, index: 0))
        let second = try #require(atlas.frame(motion: motion, index: 1))
        #expect(first.width == 96 && first.height == 104)
        let bytes = try #require(first.dataProvider?.data) as Data
        let next = try #require(second.dataProvider?.data) as Data
        #expect(bytes != next)
        let alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
        #expect(alpha.contains(0))
        #expect(alpha.contains(255))
        #expect(atlas.frame(motion: motion, index: motion.frameCount - 1) != nil)
        #expect(atlas.frame(motion: motion, index: motion.frameCount) == nil)
        #expect(atlas.frame(motion: motion, index: -1) == nil)
    }
}

@MainActor @Test func missingAssetsDoNotAddASelectableSystemPlaceholder() async {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-pets-\(UUID().uuidString)")
    let library = PetLibrary(home: missing, cacheDirectory: missing)
    #expect(library.pets.isEmpty)
    #expect(library.atlas == nil)
    #expect(!(await library.synchronize(applicationURL: nil, selectedID: IslandSettings.defaultPetID, force: false)))
    #expect(library.pets.isEmpty)
    #expect(library.selectedID == IslandSettings.defaultPetID)
    #expect(library.atlas == nil)
}

@MainActor @Test func pendingApprovalOverridesCommandErrorsWithoutInventingASessionTitle() {
    let previousLanguage = L10n.shared.language
    L10n.shared.configure(language: .zhHans)
    defer { L10n.shared.configure(language: previousLanguage) }
    let model = IslandModel()
    model.connection = .connected
    model.sessionTitle = "不确定是否属于该审批的会话"
    model.summary = .reduce([.running])
    model.activity = .commandFailed
    model.approvalUIIsPending = true
    #expect(model.title == "Codex")
    #expect(model.detail == "等待批准")
    #expect(model.effectState == .needsInput)
    #expect(model.petMotion == .waiting)
    model.approvalUIIsPending = false
    #expect(model.title == model.sessionTitle)
    #expect(model.effectState == .blocked)
    model.summary = .reduce([.needsInput])
    #expect(model.effectState == .needsInput)
    model.summary = .reduce([])
    model.activity = .idle
    #expect(model.detail == "等待新任务")
}
