import AppKit
import IslandCore
import Observation

enum ConnectionState: Equatable {
    case connecting, connected, unsupported, unavailable, appNotRunning
}

@MainActor @Observable
final class IslandModel {
    let preferences: IslandPreferences
    let pets = PetLibrary()
    var isClickThrough = false
    var approvalUIIsPending = false
    var approvalAccessMessage = "审批窗口识别未开启"
    var connection: ConnectionState = .connecting
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
    var motionPaused: Bool { animationsPaused || !preferences.values.animationsEnabled }

    var title: String {
        // AX proves a visible decision, but supplies no reliable thread ID.
        approvalUIIsPending ? "Codex" : sessionTitle ?? "Codex"
    }

    var detail: String? {
        if launchFailed { return "无法打开 Codex" }
        if approvalUIIsPending { return "等待批准" }
        return switch connection {
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
        }
    }

    var sourceBadge: String? {
        isDemo ? "演示" : isExternalFeed ? "外部" : isLocalFeed ? "本机" : nil
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
        let prefix = isDemo ? "演示 · " : isExternalFeed ? "外部 · " : ""
        return prefix + (detail ?? "同步中")
    }
    var isExpanded: Bool { true }
    var shouldShow: Bool {
        if !preferences.values.isVisible { return false }
        if isDemo { return true }
        if connection == .appNotRunning { return false }
        return true
    }

    var accessibilityDescription: String {
        [title, detail, sourceBadge, "宠物\(pets.displayName)", isClickThrough ? "临时穿透中" : nil,
         connection == .connected && !approvalUIIsPending ? summary.detail : nil, "打开 Codex"].compactMap { $0 }.joined(separator: "，")
    }
}
