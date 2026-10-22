import Foundation

/// Horizontal travel inside the island's padded content, below any notch.
public struct PetRoamingBounds: Sendable, Equatable {
    public let maximumX: Double
    public var dockX: Double { maximumX }
    public var canRoam: Bool { maximumX >= 16 }

    public init(stageWidth: Double, spriteWidth: Double = 48) {
        let width = stageWidth.isFinite ? max(0, stageWidth) : 0
        let sprite = spriteWidth.isFinite ? max(0, spriteWidth) : 48
        maximumX = max(0, width - sprite)
    }

    public func clamped(_ position: Double) -> Double {
        position.isFinite ? min(maximumX, max(0, position)) : dockX
    }
}

/// A short walk, then rest: no long traversal or endless gait loop.
public struct PetRoamingLeg: Sendable {
    public let startX: Double
    public let destinationX: Double
    public let motion: PetMotion
    public let cycleCount: Int
    public var durationMilliseconds: Int { cycleCount * motion.durationMilliseconds }

    public init(bounds: PetRoamingBounds, startX: Double, destinationFraction: Double) {
        let start = bounds.clamped(startX)
        self.startX = start
        guard bounds.canRoam else {
            destinationX = start
            motion = .idle
            cycleCount = 0
            return
        }
        let fraction = destinationFraction.isFinite ? min(1, max(0, destinationFraction)) : 0.5
        var target = bounds.maximumX * fraction
        if abs(target - start) < 16 {
            target = bounds.clamped(start + (start < bounds.maximumX / 2 ? 36 : -36))
        }
        // One gait takes 1.06s, advancing at most 36pt. Limit a walk to three
        // gaits; further movement waits for the next random resting interval.
        let displacement = min(108, max(-108, target - start))
        destinationX = bounds.clamped(start + displacement)
        motion = destinationX < start ? .walkingLeft : .walkingRight
        cycleCount = min(3, max(1, Int(ceil(abs(destinationX - start) / 36))))
    }
}

public struct PetWalkingSample: Sendable, Equatable {
    public let positionX: Double
    public let motion: PetMotion
    public let frameIndex: Int
    public let hasArrived: Bool
}

/// Position and gait are sampled from the same elapsed time. No view animation
/// transaction or model target is used as a substitute for the visible position.
public struct PetWalk: Sendable {
    public let startX: Double
    public let destinationX: Double
    public let startedAt: Date
    public let motion: PetMotion
    public let durationMilliseconds: Int
    private let frameDurations: [Int]
    private let gaitDuration: Int

    public init?(startX: Double, destinationX: Double, startedAt: Date, timing: PetTimingProfile = .compatibility) {
        let distance = abs(destinationX - startX)
        guard startX.isFinite, destinationX.isFinite, distance.isFinite, distance > 0.5 else { return nil }
        let cycles = ceil(distance / 36)
        let direction: PetMotion = destinationX < startX ? .walkingLeft : .walkingRight
        let gait = timing.duration(for: direction)
        guard cycles < Double(Int.max / gait) else { return nil }
        self.startX = startX
        self.destinationX = destinationX
        self.startedAt = startedAt
        motion = direction
        frameDurations = timing.durations(for: direction)
        gaitDuration = gait
        durationMilliseconds = max(1, Int(cycles)) * gait
    }

    public func sample(at date: Date) -> PetWalkingSample {
        sample(elapsed: date.timeIntervalSince(startedAt))
    }

    public func sample(elapsed: TimeInterval) -> PetWalkingSample {
        let duration = Double(durationMilliseconds) / 1000
        let time = elapsed.isNaN ? 0 : min(duration, max(0, elapsed))
        guard time < duration else {
            return PetWalkingSample(positionX: destinationX, motion: .idle, frameIndex: 0, hasArrived: true)
        }
        let position = startX + (destinationX - startX) * (time / duration)
        var frameTime = (time * 1000).truncatingRemainder(dividingBy: Double(gaitDuration))
        for (index, milliseconds) in frameDurations.enumerated() {
            if frameTime < Double(milliseconds) {
                return PetWalkingSample(positionX: position, motion: motion, frameIndex: index, hasArrived: false)
            }
            frameTime -= Double(milliseconds)
        }
        return PetWalkingSample(positionX: position, motion: motion, frameIndex: 0, hasArrived: false)
    }
}
