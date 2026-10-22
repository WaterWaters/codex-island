import Testing
import Foundation
@testable import IslandCore

@Test func petMotionUsesSemanticAtlasRows() {
    #expect(PetMotion(state: .idle) == .idle)
    #expect(PetMotion(state: .running) == .running)
    #expect(PetMotion(state: .needsInput) == .waiting)
    #expect(PetMotion(state: .blocked) == .failed)
    #expect(PetMotion(state: .ready) == .review)
    #expect(PetMotion.running.row == 7)
    #expect(PetMotion.waiting.row == 6)
    #expect(PetMotion.failed.row == 5)
    #expect(PetMotion.walkingLeft.row == 2)
    #expect(PetMotion.walkingRight.row == 1)
}

@Test func petTimingMatchesObservedCodexFrameDurations() {
    #expect(PetMotion.running.frameDurationsMilliseconds == [120, 120, 120, 120, 120, 220])
    #expect(PetMotion.running.durationMilliseconds == 820)
    #expect(PetMotion.waiting.durationMilliseconds == 1010)
    #expect(PetMotion.failed.durationMilliseconds == 1220)
    #expect(PetMotion.review.durationMilliseconds == 1030)
    #expect(PetMotion.idle.frameDurationsMilliseconds == [1680, 660, 660, 840, 840, 1920])
    #expect(PetMotion.idle.durationMilliseconds == 6600)
    #expect(PetMotion.walkingLeft.durationMilliseconds == 1060)
    #expect(PetMotion.walkingRight.frameDurationsMilliseconds == [120, 120, 120, 120, 120, 120, 120, 220])
}

@Test func petPlaysOneCompletePassThenRestsInsteadOfLooping() {
    for motion in PetMotion.allCases {
        let plan = PetPlaybackPlan(motion: motion, restFraction: 0.5)
        let active = plan.steps.filter { !$0.isResting }
        #expect(active.count == motion.frameCount)
        #expect(active.map(\.frameIndex) == Array(0..<motion.frameCount))
        #expect(active.allSatisfy { $0.motion == motion })
        #expect(active.reduce(0) { $0 + $1.durationMilliseconds } == motion.durationMilliseconds)
        #expect(plan.steps.last?.isResting == true)
        #expect(plan.steps.last?.motion == .idle)
        #expect(plan.steps.last?.frameIndex == 0)
    }
}

@Test func randomPetRestIsBoundedAndVariesBetweenPasses() {
    #expect(PetPlaybackPlan(motion: .running, restFraction: 0).steps.last?.durationMilliseconds == 6600)
    #expect(PetPlaybackPlan(motion: .running, restFraction: 1).steps.last?.durationMilliseconds == 19800)
    #expect(PetPlaybackPlan(motion: .running, restFraction: 0.5).steps.last?.durationMilliseconds == 13200)
    for fraction in [-100.0, 100.0, Double.nan, .infinity] {
        let delay = PetPlaybackPlan(motion: .running, restFraction: fraction).steps.last!.durationMilliseconds
        #expect((6600...19800).contains(delay))
    }
}
