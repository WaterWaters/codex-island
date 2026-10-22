import Testing
import Foundation
@testable import IslandCore

@Test func idleRoamingWalksInTheTravelDirectionWithShortLegs() {
    let bounds = PetRoamingBounds(stageWidth: 316)
    let left = PetRoamingLeg(bounds: bounds, startX: bounds.dockX, destinationFraction: 0)
    #expect(left.motion == .walkingLeft)
    #expect(left.destinationX == 160)
    #expect(left.cycleCount == 3)
    #expect(left.durationMilliseconds == 3180)
    let right = PetRoamingLeg(bounds: bounds, startX: 0, destinationFraction: 1)
    #expect(right.motion == .walkingRight)
    #expect(right.destinationX == 108)
    #expect(right.cycleCount == 3)
}

@Test func randomRoamingTargetsStayInsidePaddedContent() {
    for width in [80.0, 160, 316, 560] {
        let bounds = PetRoamingBounds(stageWidth: width)
        for start in [-20.0, 0, 40, 300, 1000, .nan] {
            for sample in [-1.0, 0, 0.25, 0.5, 0.75, 1, 2, .nan] {
                let leg = PetRoamingLeg(bounds: bounds, startX: start, destinationFraction: sample)
                #expect((0...bounds.maximumX).contains(leg.startX))
                #expect((0...bounds.maximumX).contains(leg.destinationX))
                #expect(abs(leg.destinationX - leg.startX) <= 108)
                #expect((1...3).contains(leg.cycleCount))
                #expect(leg.destinationX != leg.startX)
                #expect(leg.motion == (leg.destinationX < leg.startX ? .walkingLeft : .walkingRight))
            }
        }
    }
}

@Test func narrowOrInvalidStagesDoNotWalk() {
    for width in [-20.0, 0, 48, 60, .infinity, .nan] {
        let bounds = PetRoamingBounds(stageWidth: width)
        let leg = PetRoamingLeg(bounds: bounds, startX: 100, destinationFraction: 0.5)
        #expect(!bounds.canRoam)
        #expect(leg.startX == leg.destinationX)
        #expect(leg.cycleCount == 0)
        #expect(leg.durationMilliseconds == 0)
        #expect(leg.motion == .idle)
    }
}

@Test func walkingPositionAndGaitAdvanceOnTheSameClock() throws {
    let route = try #require(PetWalk(startX: 268, destinationX: 160, startedAt: .distantPast))
    #expect(route.sample(elapsed: 0).positionX == 268)
    #expect(route.sample(elapsed: 0).frameIndex == 0)
    let midway = route.sample(elapsed: 1.59)
    #expect(abs(midway.positionX - 214) < 0.0001)
    #expect(midway.motion == .walkingLeft)
    #expect(!midway.hasArrived)
    let firstStep = route.sample(elapsed: 0.121)
    #expect(firstStep.frameIndex == 1)
    #expect(firstStep.positionX < 268 && firstStep.positionX > 160)
    let arrived = route.sample(elapsed: 3.18)
    #expect(arrived.positionX == 160)
    #expect(arrived.hasArrived)
    #expect(arrived.motion == .idle)
}

@Test func workTransitionWalksFromInterruptedPresentationPosition() throws {
    let outgoing = try #require(PetWalk(startX: 268, destinationX: 160, startedAt: .distantPast))
    let visible = outgoing.sample(elapsed: 1).positionX
    let returning = try #require(PetWalk(startX: visible, destinationX: 268, startedAt: .distantPast))
    #expect(returning.motion == .walkingRight)
    #expect(returning.sample(elapsed: 0).positionX == visible)
    #expect(returning.sample(elapsed: 0).positionX != outgoing.destinationX)
    #expect(returning.sample(elapsed: 0).positionX != 268)
    let halfway = returning.sample(elapsed: Double(returning.durationMilliseconds) / 2000)
    #expect(halfway.positionX > visible && halfway.positionX < 268)
    #expect(halfway.motion == .walkingRight)
    #expect(returning.sample(elapsed: 100).positionX == 268)
}

@Test func walkingSamplesAreMonotonicAndClampedAtBothEnds() throws {
    for (start, end) in [(0.0, 268.0), (268, 40)] {
        let route = try #require(PetWalk(startX: start, destinationX: end, startedAt: .distantPast))
        var previous = start
        for i in 0...200 {
            let sample = route.sample(elapsed: Double(route.durationMilliseconds) / 1000 * Double(i) / 200)
            #expect((min(start, end)...max(start, end)).contains(sample.positionX))
            #expect(end > start ? sample.positionX >= previous : sample.positionX <= previous)
            #expect((0..<sample.motion.frameCount).contains(sample.frameIndex))
            previous = sample.positionX
        }
        #expect(route.sample(elapsed: -1).positionX == start)
        #expect(route.sample(elapsed: .infinity).positionX == end)
        #expect(route.sample(elapsed: .nan).positionX == start)
    }
    #expect(PetWalk(startX: 20, destinationX: 20, startedAt: .distantPast) == nil)
    #expect(PetWalk(startX: .nan, destinationX: 20, startedAt: .distantPast) == nil)
}
