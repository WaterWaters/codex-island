import AppKit
import DesktopFeed
import IslandCore
import Observation

enum ConnectionState: Equatable {
    case connecting, connected, unsupported, unavailable, appNotRunning, appNotInstalled, missingLocalData
}

@MainActor @Observable
final class IslandModel {
    let preferences: IslandPreferences
    let pets = PetLibrary()
    var isClickThrough = false
    var approvalUIIsPending = false
    var approvalAccessMessage = "审批窗口识别未开启"
    var connection: ConnectionState = .connecting
    var localFeedHealth: FeedHealth?
    var sourceFailureReason: SourceFailureReason?
    var codexVersion: String?
    var summary = ActivitySummary.reduce([])
    var sessionTitle: String?
    var activity: SessionActivity?
    var launchFailed = false
    var isDemo = false
    var isExternalFeed = false
    var isLocalFeed = false
    var isHovered = false
    var animationsPaused = false

    init(preferences: IslandPreferences = IslandPreferences()) { self.preferences = preferences }
    var motionPaused: Bool { animationsPaused || !preferences.values.isVisible || !preferences.values.animationsEnabled || preferences.values.appearancePreset == .quiet || preferences.values.appearancePreset == .highContrast }

    var title: String {
        // AX proves a visible decision, but supplies no reliable thread ID.
        preferences.values.hideSessionTitle || approvalUIIsPending ? "Codex" : sessionTitle ?? "Codex"
    }

    var detail: String? {
        if launchFailed { return L10n.text("无法打开 Codex") }
        if approvalUIIsPending { return L10n.text("等待批准") }
        let source: String? = switch connection {
        case .connected:
            switch summary.state {
            case .needsInput: SessionActivity.needsInput.title
            case .blocked: SessionActivity.failed.title
            case .ready: summary.state.title
            case .idle: SessionActivity.idle.title
            case .running: (activity ?? .working).title
            }
        case .connecting: "同步中"
        case .unsupported: "暂无法同步"
        case .unavailable: "状态暂不可用"
        case .appNotRunning: "Codex 未运行"
        case .appNotInstalled: "未找到 Codex"
        case .missingLocalData: "等待本机数据"
        }
        return source.map(L10n.text)
    }

    var sourceBadge: String? {
        isDemo ? L10n.text("演示") : isExternalFeed ? L10n.text("外部") : isLocalFeed ? L10n.text("本机") : nil
    }

    var state: WorkState { approvalUIIsPending ? .needsInput : connection == .connected ? summary.state : .idle }
    var effectState: WorkState {
        if state == .needsInput { return .needsInput }
        if launchFailed || (connection == .connected && (activity == .failed || activity == .commandFailed)) { return .blocked }
        return state
    }
    var isWorking: Bool { connection == .connected && summary.state == .running }
    var petMotion: PetMotion { PetMotion(state: effectState) }
    var displayDetail: String {
        var message = detail ?? L10n.text("同步中")
        if isDemo { message = L10n.format("island.detail", L10n.text("演示"), message) }
        else if isExternalFeed { message = L10n.format("island.detail", L10n.text("外部"), message) }
        if isLocalFeed, connection == .connected, !approvalUIIsPending, let health = localFeedHealth {
            if health.degradedThreads > 0 { message = L10n.format("island.detail", message, L10n.text("同步受限")) }
            else if !health.caughtUp { message = L10n.format("island.detail", message, L10n.text("同步中")) }
        }
        return message
    }

    var isExpanded: Bool { true }
    var shouldShow: Bool {
        if !preferences.values.isVisible { return false }
        if isDemo { return true }
        if connection == .appNotRunning || connection == .appNotInstalled { return false }
        return true
    }

    var accessibilityDescription: String {
        let extra: String?
        if summary.state != .running, summary.runningCount > 0 { extra = L10n.count("summary.other_running", summary.runningCount) }
        else if summary.state == .running, summary.runningCount > 1 { extra = L10n.count("summary.running", summary.runningCount) }
        else if summary.state == .ready, summary.primaryCount > 1 { extra = L10n.count("summary.ready", summary.primaryCount) }
        else { extra = nil }
        return [title, displayDetail, sourceBadge, L10n.format("accessibility.pet", pets.displayName),
            isClickThrough ? L10n.text("临时穿透中") : nil,
            connection == .connected && !approvalUIIsPending ? extra : nil, L10n.text("打开 Codex")]
            .compactMap { $0 }.joined(separator: ", ")
    }

    var connectionPresentation: ConnectionPresentation {
        ConnectionPresentation(connection: connection, health: localFeedHealth, isDemo: isDemo, isExternal: isExternalFeed)
    }

    var privacyDiagnostics: PrivacyDiagnostics {
        PrivacyDiagnostics(islandVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            codexVersion: codexVersion, presentation: connectionPresentation, reason: sourceFailureReason,
            health: localFeedHealth, isDemo: isDemo, isExternal: isExternalFeed)
    }
}
