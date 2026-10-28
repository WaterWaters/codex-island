import Foundation

/// A local status source. Provider identity is display metadata only; it never
/// changes the meaning of a work state.
public enum SourceProvider: String, Codable, CaseIterable, Sendable {
    case codex, claude

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }
}

public enum StatusSourceMode: String, Codable, CaseIterable, Sendable {
    case codex, claude, rotate
}

/// Provider-neutral health. Field names stay compatible with the existing
/// Codex diagnostics (`degradedThreads` / `retryingThreads`) even when the
/// unit is a Claude session.
public struct SourceHealth: Equatable, Sendable {
    public let caughtUp: Bool
    public let degradedThreads: Int
    public let retryingThreads: Int
    public let unresolvedIdentity: Bool

    public init(caughtUp: Bool, degradedThreads: Int = 0, retryingThreads: Int = 0,
                unresolvedIdentity: Bool = false) {
        self.caughtUp = caughtUp
        self.degradedThreads = degradedThreads
        self.retryingThreads = retryingThreads
        self.unresolvedIdentity = unresolvedIdentity
    }
}

public struct RotationCandidate: Equatable, Sendable {
    public let provider: SourceProvider
    public let isConnected: Bool
    public let state: WorkState
    public let lastActivityAt: Date?

    public init(provider: SourceProvider, isConnected: Bool, state: WorkState,
                lastActivityAt: Date?) {
        self.provider = provider
        self.isConnected = isConnected
        self.state = state
        self.lastActivityAt = lastActivityAt
    }
}

/// Pure display selection. Attention states (needsInput / blocked) are sticky:
/// rotation never hides them. Only active, connected providers are rotated.
public struct RotationPolicy: Equatable, Sendable {
    public var dwell: TimeInterval
    public var minimumHold: TimeInterval
    public var resumeAfterHover: TimeInterval

    public init(dwell: TimeInterval = 6, minimumHold: TimeInterval = 3,
                resumeAfterHover: TimeInterval = 2) {
        self.dwell = dwell
        self.minimumHold = minimumHold
        self.resumeAfterHover = resumeAfterHover
    }

    public func select(mode: StatusSourceMode, current: SourceProvider,
                       candidates: [RotationCandidate], lastSwitchAt: Date?,
                       hovered: Bool, pausedUntil: Date?, now: Date) -> SourceProvider {
        switch mode {
        case .codex: return .codex
        case .claude: return .claude
        case .rotate: break
        }
        let connected = candidates.filter(\.isConnected)
        guard !connected.isEmpty else { return current }
        let active = connected.filter { $0.state != .idle }
        let pool = active.isEmpty ? connected : active

        let attention = pool.filter { $0.state == .needsInput || $0.state == .blocked }
        if !attention.isEmpty {
            if let currentCandidate = attention.first(where: { $0.provider == current }) {
                let stronger = attention.filter { rank($0.state) > rank(currentCandidate.state) }
                if let best = stronger.sorted(by: attentionOrder).first { return best.provider }
                return current
            }
            return attention.sorted(by: attentionOrder).first!.provider
        }

        if pool.count == 1 { return pool[0].provider }

        let paused = hovered || (pausedUntil.map { now < $0 } ?? false)
        if paused {
            return pool.contains(where: { $0.provider == current }) ? current : pool.sorted(by: recencyOrder).first!.provider
        }
        guard pool.contains(where: { $0.provider == current }) else {
            return pool.sorted(by: recencyOrder).first!.provider
        }
        guard let lastSwitchAt else { return current }
        guard now.timeIntervalSince(lastSwitchAt) >= max(dwell, minimumHold) else { return current }

        let ordered = pool.sorted(by: stableOrder)
        guard let index = ordered.firstIndex(where: { $0.provider == current }) else {
            return ordered[0].provider
        }
        return ordered[(index + 1) % ordered.count].provider
    }

    private func rank(_ state: WorkState) -> Int {
        switch state {
        case .needsInput: 4
        case .blocked: 3
        case .ready: 2
        case .running: 1
        case .idle: 0
        }
    }

    private func attentionOrder(_ left: RotationCandidate, _ right: RotationCandidate) -> Bool {
        let leftRank = rank(left.state), rightRank = rank(right.state)
        if leftRank != rightRank { return leftRank > rightRank }
        return recencyOrder(left, right)
    }

    private func recencyOrder(_ left: RotationCandidate, _ right: RotationCandidate) -> Bool {
        switch (left.lastActivityAt, right.lastActivityAt) {
        case let (leftDate?, rightDate?) where leftDate != rightDate:
            return leftDate > rightDate
        default:
            return stableOrder(left, right)
        }
    }

    private func stableOrder(_ left: RotationCandidate, _ right: RotationCandidate) -> Bool {
        orderIndex(left.provider) < orderIndex(right.provider)
    }

    private func orderIndex(_ provider: SourceProvider) -> Int {
        SourceProvider.allCases.firstIndex(of: provider) ?? 0
    }
}
