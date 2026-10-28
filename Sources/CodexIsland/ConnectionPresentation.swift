import ClaudeFeed
import DesktopFeed
import Foundation
import IslandCore

/// Only fixed identifiers may cross the diagnostic boundary.
enum SourceFailureReason: String, Codable, Sendable {
    case missingDatabase, incompatibleSchema, databaseUnavailable, queryTimedOut
    case oversized, invalidRollout, invalidConfiguration, unknownReadFailure
    case snapshotRejected, sourceUnavailable

    init(error: Error) {
        self = (error as? FeedError).flatMap { Self(rawValue: $0.rawValue) } ?? .unknownReadFailure
    }

    init(claudeError: Error) {
        switch claudeError as? ClaudeFeedError {
        case .missingDirectory: self = .missingDatabase
        case .unreadableRegistry: self = .databaseUnavailable
        case .incompatibleSchema: self = .incompatibleSchema
        case .oversized: self = .oversized
        case .invalidConfiguration: self = .invalidConfiguration
        case .unresolvedIdentity: self = .snapshotRejected
        case .unavailable, .none: self = .unknownReadFailure
        }
    }
}

struct ConnectionPresentation {
    enum Status: String, Codable { case checking, notInstalled, notRunning, missingLocalData, incompatible, temporaryFailure, identityLimited, eventsLimited, synchronizing, connected, demo, external }
    let status: Status
    let provider: SourceProvider

    init(connection: ConnectionState, health: SourceHealth?, isDemo: Bool = false,
         isExternal: Bool = false, provider: SourceProvider = .codex) {
        self.provider = provider
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
            if let health, health.unresolvedIdentity { .identityLimited }
            else if let health, health.degradedThreads > 0 { .eventsLimited }
            else if let health, !health.caughtUp { .synchronizing }
            else { .connected }
        }
    }

    @MainActor var title: LocalizedStringResource {
        if provider == .claude {
            switch status {
            case .notInstalled: return SetupText.resource("connection.claude.not_installed.title", "未找到 Claude 应用")
            case .notRunning: return SetupText.resource("connection.claude.not_running.title", "Claude 未运行")
            case .missingLocalData: return SetupText.resource("connection.claude.missing_data.title", "尚未找到 Claude 会话数据")
            case .incompatible: return SetupText.resource("connection.claude.incompatible.title", "Claude 本机来源暂不兼容")
            case .temporaryFailure: return SetupText.resource("connection.claude.temporary_failure.title", "暂时无法读取 Claude 状态")
            case .identityLimited: return SetupText.resource("connection.claude.identity_limited.title", "已连接 · 部分 Claude 状态待确认")
            case .eventsLimited: return SetupText.resource("connection.claude.events_limited.title", "已连接 · Claude 事件同步受限")
            case .synchronizing: return SetupText.resource("connection.claude.synchronizing.title", "已连接 · 正在追平 Claude 事件")
            case .connected: return SetupText.resource("connection.claude.connected.title", "已连接本机 Claude")
            case .checking, .demo, .external: break
            }
        }
        switch status {
        case .checking: return SetupText.resource("connection.checking.title", "正在检查连接")
        case .notInstalled: return SetupText.resource("connection.not_installed.title", "未找到 Codex 应用")
        case .notRunning: return SetupText.resource("connection.not_running.title", "Codex 未运行")
        case .missingLocalData: return SetupText.resource("connection.missing_data.title", "尚未找到本机会话数据")
        case .incompatible: return SetupText.resource("connection.incompatible.title", "本机来源暂不兼容")
        case .temporaryFailure: return SetupText.resource("connection.temporary_failure.title", "暂时无法读取状态")
        case .identityLimited: return SetupText.resource("connection.identity_limited.title", "已连接 · 部分状态待确认")
        case .eventsLimited: return SetupText.resource("connection.events_limited.title", "已连接 · 事件同步受限")
        case .synchronizing: return SetupText.resource("connection.synchronizing.title", "已连接 · 正在追平事件")
        case .connected: return SetupText.resource("connection.connected.title", "已连接本机 Codex")
        case .demo: return SetupText.resource("connection.demo.title", "演示模式 · 非真实连接")
        case .external: return SetupText.resource("connection.external.title", "正在使用显式外部状态")
        }
    }

    @MainActor var nextStep: LocalizedStringResource {
        if provider == .claude {
            switch status {
            case .notInstalled: return SetupText.resource("connection.claude.not_installed.next", "请先安装 Claude 应用并打开一个本机会话，然后返回这里重新同步。")
            case .notRunning: return SetupText.resource("connection.claude.not_running.next", "打开 Claude 并开始一个本机会话后会自动重新检查；也可以手动重新同步。")
            case .missingLocalData: return SetupText.resource("connection.claude.missing_data.next", "请先在 Claude Code 中打开或创建一个本机会话。若使用自定义配置目录，请确认启动时的 CLAUDE_CONFIG_DIR，再重新同步。")
            case .incompatible: return SetupText.resource("connection.claude.incompatible.next", "当前 Claude Code 数据结构不受适配器支持。请检查 Codex Island 更新；可复制脱敏诊断帮助定位。")
            case .temporaryFailure: return SetupText.resource("connection.claude.temporary_failure.next", "应用会自动重试。请确认 Claude Code 可正常使用；也可重新同步或复制脱敏诊断。")
            case .identityLimited: return SetupText.resource("connection.claude.identity_limited.next", "暂时无法确认部分 Claude 会话状态。已确认的活动仍会显示，未确认的状态不代表空闲。")
            case .eventsLimited: return SetupText.resource("connection.claude.events_limited.next", "基础活动仍可显示，但 Claude 事件尚未完整追平；应用正在有界重试。")
            case .synchronizing: return SetupText.resource("connection.claude.synchronizing.next", "正在增量读取 Claude 事件。请稍候，追平前不将等待状态视为完整。")
            case .connected: return SetupText.resource("connection.claude.connected.next", "连接正常。状态会自动刷新；若与 Claude 不一致，可重新同步。")
            case .checking, .demo, .external: break
            }
        }
        switch status {
        case .checking: return SetupText.resource("connection.checking.next", "正在检查本机状态。若持续没有结果，可重新同步。")
        case .notInstalled: return SetupText.resource("connection.not_installed.next", "请先安装 Codex 桌面应用，打开并登录，然后返回这里重新同步。")
        case .notRunning: return SetupText.resource("connection.not_running.next", "打开 Codex 后会自动重新检查连接；也可以手动重新同步。")
        case .missingLocalData: return SetupText.resource("connection.missing_data.next", "请先在 Codex 中打开或创建一个本机会话。若使用自定义数据目录，请确认启动时的 CODEX_HOME 配置，再重新同步。")
        case .incompatible: return SetupText.resource("connection.incompatible.next", "当前本地数据结构不受适配器支持。请检查 Codex Island 更新；可复制脱敏诊断帮助定位。")
        case .temporaryFailure: return SetupText.resource("connection.temporary_failure.next", "应用会自动重试。请确认 Codex 可正常使用；若仍失败，可重新同步或复制脱敏诊断。")
        case .identityLimited: return SetupText.resource("connection.identity_limited.next", "暂时无法确认部分会话状态。已确认的活动仍会显示，应用会自动重试；也可以重新同步。未确认的状态不代表空闲。")
        case .eventsLimited: return SetupText.resource("connection.events_limited.next", "基础活动仍可显示，但问答事件尚未完整追平。应用正在有界重试；可重新同步。受限期间不将问答状态视为完整。")
        case .synchronizing: return SetupText.resource("connection.synchronizing.next", "正在增量读取事件。请稍候，追平前不将问答状态视为完整。")
        case .connected: return SetupText.resource("connection.connected.next", "连接正常。状态会自动刷新；若与 Codex 不一致，可重新同步。")
        case .demo: return SetupText.resource("connection.demo.next", "这里显示合成状态，不能用作 Codex 安装、连接或恢复证据。此实例的设置与引导进度不会写入正式偏好。")
        case .external: return SetupText.resource("connection.external.next", "来源由启动参数指定，不能用作本机 Codex 连接证据。请检查外部状态提供方。")
        }
    }

    var offersOpenApplication: Bool { ![.notInstalled, .demo, .external].contains(status) }
    var offersOpenCodex: Bool { offersOpenApplication }
    @MainActor var openLabel: LocalizedStringResource { provider == .codex ? SetupText.openCodex : SetupText.openClaude }
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
    let claudeVersion: String
    let source: String
    let sourceMode: String
    let displayedSource: String
    let connection: ConnectionPresentation.Status
    let reason: SourceFailureReason?
    let caughtUp: Bool?
    let degradedThreads: Int?
    let retryingThreads: Int?
    let unresolvedIdentity: Bool?
    let claudeConnection: ConnectionPresentation.Status
    let claudeCaughtUp: Bool?
    let claudeDegradedThreads: Int?
    let claudeRetryingThreads: Int?
    let claudeUnresolvedIdentity: Bool?

    init(islandVersion: String?, codexVersion: String?, claudeVersion: String?,
         codex: ProviderStatus, claude: ProviderStatus, displayed: SourceProvider,
         sourceMode: StatusSourceMode, isDemo: Bool, isExternal: Bool) {
        self.islandVersion = Self.safeVersion(islandVersion)
        self.codexVersion = Self.safeVersion(codexVersion)
        self.claudeVersion = Self.safeVersion(claudeVersion)
        source = isDemo ? "demo" : isExternal ? "explicit-file" : "local-session-history-v1"
        self.sourceMode = sourceMode.rawValue
        displayedSource = displayed.rawValue
        let codexPresentation = ConnectionPresentation(connection: codex.connection, health: codex.health,
                                                       isDemo: isDemo, isExternal: isExternal, provider: .codex)
        let claudePresentation = ConnectionPresentation(connection: claude.connection, health: claude.health,
                                                        isDemo: isDemo, isExternal: isExternal, provider: .claude)
        connection = codexPresentation.status
        reason = codex.failureReason
        caughtUp = codex.health?.caughtUp
        degradedThreads = codex.health.map { max(0, $0.degradedThreads) }
        retryingThreads = codex.health.map { max(0, $0.retryingThreads) }
        unresolvedIdentity = codex.health?.unresolvedIdentity
        claudeConnection = claudePresentation.status
        claudeCaughtUp = claude.health?.caughtUp
        claudeDegradedThreads = claude.health.map { max(0, $0.degradedThreads) }
        claudeRetryingThreads = claude.health.map { max(0, $0.retryingThreads) }
        claudeUnresolvedIdentity = claude.health?.unresolvedIdentity
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
