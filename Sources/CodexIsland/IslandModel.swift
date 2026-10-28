import AppKit
import IslandCore
import Observation

enum ConnectionState: Equatable {
    case connecting, connected, unsupported, unavailable, appNotRunning, appNotInstalled, missingLocalData
}

struct ProviderStatus: Equatable {
    var connection: ConnectionState = .connecting
    var health: SourceHealth?
    var failureReason: SourceFailureReason?
    var summary: ActivitySummary = .reduce([])
    var title: String?
    var activity: SessionActivity?
    var observedAt: Date?
}

@MainActor @Observable
final class IslandModel {
    let preferences: IslandPreferences
    let pets = PetLibrary()
    var isClickThrough = false
    var approvalUIIsPending = false
    var approvalAccessMessage = "审批窗口识别未开启"
    var codexVersion: String?
    var claudeVersion: String?
    var launchFailed = false
    var isDemo = false
    var isExternalFeed = false
    var isLocalFeed = false
    var isHovered = false
    var animationsPaused = false

    var displayedProvider: SourceProvider = .codex
    private var statuses: [SourceProvider: ProviderStatus] = [:]
    private var lastSwitchAt: Date?
    private var rotationPausedUntil: Date?
    let rotationPolicy = RotationPolicy()

    init(preferences: IslandPreferences = IslandPreferences()) { self.preferences = preferences }
    var motionPaused: Bool { animationsPaused || !preferences.values.isVisible || !preferences.values.animationsEnabled || preferences.values.appearancePreset == .quiet || preferences.values.appearancePreset == .highContrast }

    // MARK: provider status

    func status(for provider: SourceProvider) -> ProviderStatus {
        statuses[provider] ?? ProviderStatus()
    }

    func apply(provider: SourceProvider, connection: ConnectionState, health: SourceHealth? = nil,
               reason: SourceFailureReason? = nil, summary: ActivitySummary = .reduce([]),
               title: String? = nil, activity: SessionActivity? = nil, observedAt: Date? = nil) {
        statuses[provider] = ProviderStatus(connection: connection, health: health,
                                            failureReason: reason, summary: summary,
                                            title: title, activity: activity,
                                            observedAt: observedAt)
    }

    func resetStatus(_ provider: SourceProvider, connection: ConnectionState = .connecting) {
        statuses[provider] = ProviderStatus(connection: connection)
    }

    /// Compatibility accessors read and write the currently displayed provider.
    /// Existing views and tests keep using the same property names.
    var connection: ConnectionState {
        get { status(for: displayedProvider).connection }
        set { statuses[displayedProvider, default: ProviderStatus()].connection = newValue }
    }
    var localFeedHealth: SourceHealth? {
        get { status(for: displayedProvider).health }
        set { statuses[displayedProvider, default: ProviderStatus()].health = newValue }
    }
    var sourceFailureReason: SourceFailureReason? {
        get { status(for: displayedProvider).failureReason }
        set { statuses[displayedProvider, default: ProviderStatus()].failureReason = newValue }
    }
    var summary: ActivitySummary {
        get { status(for: displayedProvider).summary }
        set { statuses[displayedProvider, default: ProviderStatus()].summary = newValue }
    }
    var sessionTitle: String? {
        get { status(for: displayedProvider).title }
        set { statuses[displayedProvider, default: ProviderStatus()].title = newValue }
    }
    var activity: SessionActivity? {
        get { status(for: displayedProvider).activity }
        set { statuses[displayedProvider, default: ProviderStatus()].activity = newValue }
    }

    var providerName: String { displayedProvider.displayName }
    var showsProviderIdentity: Bool {
        preferences.values.sourceMode != .codex || displayedProvider == .claude
    }

    // MARK: display

    var title: String {
        let fallback = providerName
        // AX proves a visible Codex decision, but supplies no reliable thread ID.
        if preferences.values.hideSessionTitle { return fallback }
        if displayedProvider == .codex && approvalUIIsPending { return fallback }
        return sessionTitle ?? fallback
    }

    var detail: String? {
        if launchFailed { return L10n.format("state.open_provider_failed", providerName) }
        if displayedProvider == .codex && approvalUIIsPending { return L10n.text("等待批准") }
        switch connection {
        case .connected:
            switch summary.state {
            case .needsInput: return L10n.text(SessionActivity.needsInput.title)
            case .blocked: return L10n.text(SessionActivity.failed.title)
            case .ready: return L10n.text(summary.state.title)
            case .idle: return localFeedHealth?.unresolvedIdentity == true
                ? L10n.text("状态暂不可用") : L10n.text(SessionActivity.idle.title)
            case .running: return L10n.text((activity ?? .working).title)
            }
        case .connecting: return L10n.text("同步中")
        case .unsupported: return L10n.text("暂无法同步")
        case .unavailable: return L10n.text("状态暂不可用")
        case .appNotRunning: return L10n.format("state.provider_not_running", providerName)
        case .appNotInstalled: return L10n.format("state.provider_not_installed", providerName)
        case .missingLocalData: return L10n.text("等待本机数据")
        }
    }

    var sourceBadge: String? {
        if isDemo { return L10n.text("演示") }
        if isExternalFeed { return L10n.text("外部") }
        return showsProviderIdentity ? providerName : nil
    }

    var state: WorkState {
        displayedProvider == .codex && approvalUIIsPending
            ? .needsInput : connection == .connected ? summary.state : .idle
    }
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
        if isLocalFeed, connection == .connected, let health = localFeedHealth,
           health.unresolvedIdentity || !(displayedProvider == .codex && approvalUIIsPending) {
            if health.unresolvedIdentity || health.degradedThreads > 0 {
                message = L10n.format("island.detail", message, L10n.text("同步受限"))
            } else if !health.caughtUp {
                message = L10n.format("island.detail", message, L10n.text("同步中"))
            }
        }
        if showsProviderIdentity {
            message = L10n.format("island.provider_detail", providerName, message)
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
        return [showsProviderIdentity ? providerName : nil, title, displayDetail, sourceBadge,
            preferences.values.displayMode == .mini ? nil : L10n.format("accessibility.pet", pets.displayName),
            isClickThrough ? L10n.text("临时穿透中") : nil,
            connection == .connected && !(displayedProvider == .codex && approvalUIIsPending) ? extra : nil,
            L10n.format("island.switch_hint_provider", providerName)]
            .compactMap { $0 }.joined(separator: ", ")
    }

    func connectionPresentation(for provider: SourceProvider) -> ConnectionPresentation {
        let status = status(for: provider)
        return ConnectionPresentation(connection: status.connection, health: status.health,
                                      isDemo: isDemo, isExternal: isExternalFeed, provider: provider)
    }
    var connectionPresentation: ConnectionPresentation { connectionPresentation(for: displayedProvider) }

    var privacyDiagnostics: PrivacyDiagnostics {
        PrivacyDiagnostics(islandVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            codexVersion: codexVersion, claudeVersion: claudeVersion,
            codex: status(for: .codex), claude: status(for: .claude),
            displayed: displayedProvider, sourceMode: preferences.values.sourceMode,
            isDemo: isDemo, isExternal: isExternalFeed)
    }

    // MARK: rotation

    func advanceRotation(now: Date) {
        let candidates = SourceProvider.allCases.map { provider -> RotationCandidate in
            let status = status(for: provider)
            return RotationCandidate(provider: provider,
                                     isConnected: status.connection == .connected,
                                     state: status.connection == .connected ? status.summary.state : .idle,
                                     lastActivityAt: status.observedAt)
        }
        let next = rotationPolicy.select(mode: preferences.values.sourceMode,
                                         current: displayedProvider, candidates: candidates,
                                         lastSwitchAt: lastSwitchAt, hovered: isHovered,
                                         pausedUntil: rotationPausedUntil, now: now)
        if next != displayedProvider {
            displayedProvider = next
            lastSwitchAt = now
        } else if lastSwitchAt == nil {
            lastSwitchAt = now
        }
    }

    func setHovered(_ hovered: Bool, now: Date = Date()) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        if !hovered { rotationPausedUntil = now.addingTimeInterval(rotationPolicy.resumeAfterHover) }
    }

    func resetRotationTiming() {
        lastSwitchAt = nil
        rotationPausedUntil = nil
    }
}
