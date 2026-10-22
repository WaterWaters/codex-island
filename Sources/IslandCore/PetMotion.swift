import Foundation

/// Rows in the existing Codex pet atlas, not newly generated artwork.
public enum PetMotion: String, CaseIterable, Sendable {
    case idle, running, waiting, failed, review, walkingLeft, walkingRight

    public init(state: WorkState) {
        self = switch state {
        case .idle: .idle
        case .running: .running
        case .needsInput: .waiting
        case .blocked: .failed
        case .ready: .review
        }
    }

    public var row: Int {
        switch self {
        case .idle: 0
        case .walkingRight: 1
        case .walkingLeft: 2
        case .failed: 5
        case .waiting: 6
        case .running: 7
        case .review: 8
        }
    }

    public var frameCount: Int {
        switch self {
        case .failed, .walkingLeft, .walkingRight: 8
        default: 6
        }
    }
    /// Observed in the installed Codex's shared pet renderer (y6s / J$).
    /// These are compatibility values, not access to its runtime variables.
    public static let timingSourceVersion = "26.1013.40934"
    public static let idleDurationMultiplier = 6

    public var frameDurationsMilliseconds: [Int] {
        switch self {
        case .idle: [280, 110, 110, 140, 140, 320].map { $0 * Self.idleDurationMultiplier }
        case .running: Array(repeating: 120, count: 5) + [220]
        case .walkingLeft, .walkingRight: Array(repeating: 120, count: 7) + [220]
        case .waiting: Array(repeating: 150, count: 5) + [260]
        case .failed: Array(repeating: 140, count: 7) + [240]
        case .review: Array(repeating: 150, count: 5) + [280]
        }
    }

    public var durationMilliseconds: Int { frameDurationsMilliseconds.reduce(0, +) }
}

public struct PetPlaybackStep: Sendable, Equatable {
    public let motion: PetMotion
    public let frameIndex: Int
    public let durationMilliseconds: Int
    public let isResting: Bool
}

/// One pass only, followed by a static resting pose. The random rest policy
/// belongs to Island; only the per-frame timing comes from observed Codex values.
public struct PetPlaybackPlan: Sendable {
    public let steps: [PetPlaybackStep]

    public init(motion: PetMotion, restFraction: Double) {
        steps = motion.frameDurationsMilliseconds.enumerated().map {
            PetPlaybackStep(motion: motion, frameIndex: $0.offset, durationMilliseconds: $0.element, isResting: false)
        } + [PetPlaybackStep(motion: .idle, frameIndex: 0,
                             durationMilliseconds: Self.restDurationMilliseconds(fraction: restFraction), isResting: true)]
    }

    public static func restDurationMilliseconds(fraction: Double, idleDuration: Int = PetMotion.idle.durationMilliseconds) -> Int {
        let bounded = fraction.isFinite ? min(1, max(0, fraction)) : 0.5
        return Int(Double(min(360_000, max(1, idleDuration))) * (1 + bounded * 2))
    }
}
