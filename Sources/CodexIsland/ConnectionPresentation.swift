import DesktopFeed
import Foundation

/// Only fixed identifiers may cross the diagnostic boundary.
enum SourceFailureReason: String, Codable, Sendable {
    case missingDatabase, incompatibleSchema, databaseUnavailable, queryTimedOut
    case oversized, invalidRollout, invalidConfiguration, unknownReadFailure
    case snapshotRejected, sourceUnavailable

    init(error: Error) {
        self = (error as? FeedError).flatMap { Self(rawValue: $0.rawValue) } ?? .unknownReadFailure
    }
}

struct ConnectionPresentation {
    enum Status: String, Codable { case checking, notInstalled, notRunning, missingLocalData, incompatible, temporaryFailure, eventsLimited, synchronizing, connected, demo, external }
    let status: Status

    init(connection: ConnectionState, health: FeedHealth?, isDemo: Bool = false, isExternal: Bool = false) {
        if isDemo { status = .demo; return }
        if isExternal, connection == .connected { status = .external; return }
        status = switch connection {
        case .connecting: .checking
        case .appNotInstalled: .notInstalled
        case .appNotRunning: .notRunning
        case .missingLocalData: .missingLocalData
        case .unsupported: .incompatible
        case .unavailable: .temporaryFailure
        case .connected:
            if let health, health.degradedThreads > 0 { .eventsLimited }
            else if let health, !health.caughtUp { .synchronizing }
            else { .connected }
        }
    }

    @MainActor var title: LocalizedStringResource {
        switch status {
        case .checking: SetupText.resource("connection.checking.title", "正在检查连接")
        case .notInstalled: SetupText.resource("connection.not_installed.title", "未找到 Codex 应用")
        case .notRunning: SetupText.resource("connection.not_running.title", "Codex 未运行")
        case .missingLocalData: SetupText.resource("connection.missing_data.title", "尚未找到本机会话数据")
        case .incompatible: SetupText.resource("connection.incompatible.title", "本机来源暂不兼容")
        case .temporaryFailure: SetupText.resource("connection.temporary_failure.title", "暂时无法读取状态")
        case .eventsLimited: SetupText.resource("connection.events_limited.title", "已连接 · 事件同步受限")
        case .synchronizing: SetupText.resource("connection.synchronizing.title", "已连接 · 正在追平事件")
        case .connected: SetupText.resource("connection.connected.title", "已连接本机 Codex")
        case .demo: SetupText.resource("connection.demo.title", "演示模式 · 非真实连接")
        case .external: SetupText.resource("connection.external.title", "正在使用显式外部状态")
        }
    }

    @MainActor var nextStep: LocalizedStringResource {
        switch status {
        case .checking: SetupText.resource("connection.checking.next", "正在检查本机状态。若持续没有结果，可重新同步。")
        case .notInstalled: SetupText.resource("connection.not_installed.next", "请先安装 Codex 桌面应用，打开并登录，然后返回这里重新同步。")
        case .notRunning: SetupText.resource("connection.not_running.next", "打开 Codex 后会自动重新检查连接；也可以手动重新同步。")
        case .missingLocalData: SetupText.resource("connection.missing_data.next", "请先在 Codex 中打开或创建一个本机会话。若使用自定义数据目录，请确认启动时的 CODEX_HOME 配置，再重新同步。")
        case .incompatible: SetupText.resource("connection.incompatible.next", "当前本地数据结构不受适配器支持。请检查 Codex Island 更新；可复制脱敏诊断帮助定位。")
        case .temporaryFailure: SetupText.resource("connection.temporary_failure.next", "应用会自动重试。请确认 Codex 可正常使用；若仍失败，可重新同步或复制脱敏诊断。")
        case .eventsLimited: SetupText.resource("connection.events_limited.next", "基础活动仍可显示，但问答事件尚未完整追平。应用正在有界重试；可重新同步。受限期间不将问答状态视为完整。")
        case .synchronizing: SetupText.resource("connection.synchronizing.next", "正在增量读取事件。请稍候，追平前不将问答状态视为完整。")
        case .connected: SetupText.resource("connection.connected.next", "连接正常。状态会自动刷新；若与 Codex 不一致，可重新同步。")
        case .demo: SetupText.resource("connection.demo.next", "这里显示合成状态，不能用作 Codex 安装、连接或恢复证据。此实例的设置与引导进度不会写入正式偏好。")
        case .external: SetupText.resource("connection.external.next", "来源由启动参数指定，不能用作本机 Codex 连接证据。请检查外部状态提供方。")
        }
    }

    var offersOpenCodex: Bool { ![.notInstalled, .demo, .external].contains(status) }
    var symbol: String {
        switch status {
        case .connected: "checkmark.circle"
        case .checking, .synchronizing: "arrow.triangle.2.circlepath"
        case .demo, .external: "info.circle"
        default: "exclamationmark.triangle"
        }
    }
}

/// Whitelist-only value. No session, title, path, payload, error description or
/// arbitrary source string can be accepted by this export API.
struct PrivacyDiagnostics: Encodable {
    let schemaVersion = 1
    let islandVersion: String
    let codexVersion: String
    let source: String
    let connection: ConnectionPresentation.Status
    let reason: SourceFailureReason?
    let caughtUp: Bool?
    let degradedThreads: Int?
    let retryingThreads: Int?

    init(islandVersion: String?, codexVersion: String?, presentation: ConnectionPresentation,
         reason: SourceFailureReason?, health: FeedHealth?, isDemo: Bool, isExternal: Bool) {
        self.islandVersion = Self.safeVersion(islandVersion)
        self.codexVersion = Self.safeVersion(codexVersion)
        source = isDemo ? "demo" : isExternal ? "explicit-file" : "local-session-history-v1"
        connection = presentation.status
        self.reason = reason
        caughtUp = health?.caughtUp
        degradedThreads = health.map { max(0, $0.degradedThreads) }
        retryingThreads = health.map { max(0, $0.retryingThreads) }
    }

    static func safeVersion(_ value: String?) -> String {
        guard let value, !value.isEmpty, value.utf8.count <= 64,
              value.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }),
              value.utf8.contains(where: { (48...57).contains($0) }) else { return "unknown" }
        return value
    }

    func json() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) }
    }
}
