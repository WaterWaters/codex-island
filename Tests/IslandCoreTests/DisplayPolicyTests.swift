import Foundation
import CoreGraphics
import Testing
@testable import IslandCore

@Test func displaySelectionIgnoresArrayOrderAndRestoresPin() {
    let preferred = "external-uuid"
    #expect(DisplaySelectionPolicy.selectedID(preferredID: nil,
                                              availableIDs: ["external-uuid", "main-uuid"],
                                              mainID: "main-uuid") == "main-uuid")
    #expect(DisplaySelectionPolicy.selectedID(preferredID: preferred,
                                              availableIDs: ["main-uuid", "external-uuid"],
                                              mainID: "main-uuid") == preferred)
    #expect(DisplaySelectionPolicy.selectedID(preferredID: preferred,
                                              availableIDs: ["main-uuid"], mainID: "main-uuid") == "main-uuid")
    #expect(DisplaySelectionPolicy.selectedID(preferredID: preferred,
                                              availableIDs: ["external-uuid", "main-uuid"],
                                              mainID: "main-uuid") == preferred)
    #expect(DisplaySelectionPolicy.selectedID(preferredID: preferred, availableIDs: [], mainID: nil) == nil)
}

@Test func displayPlacementUsesGlobalCoordinatesAndPointSizes() {
    let geometry = IslandGeometry.layout(screenWidth: 1920, notchWidth: 0, notchHeight: 0, expanded: true)
    let frame = DisplayPlacementPolicy.frame(screenFrame: CGRect(x: -1920, y: 200, width: 1920, height: 1080),
                                            visibleFrame: CGRect(x: -1920, y: 230, width: 1920, height: 1026),
                                            geometry: geometry, backingScale: 2)
    #expect(frame == CGRect(x: -1140, y: 1176, width: 360, height: 72))
    #expect(Double(frame.width) == geometry.width) // Retina must not double point dimensions.
}

@Test func notchedDisplayPlacementAttachesToItsOwnTopEdge() {
    let geometry = IslandGeometry.layout(screenWidth: 1728, notchWidth: 200, notchHeight: 38,
                                         expanded: true, contentHeight: 72)
    let frame = DisplayPlacementPolicy.frame(screenFrame: CGRect(x: 1600, y: -1117, width: 1728, height: 1117),
                                            visibleFrame: CGRect(x: 1600, y: -1080, width: 1728, height: 1042),
                                            geometry: geometry, backingScale: 2)
    #expect(frame.maxY == 0)
    #expect(frame.midX == 2464)
    #expect(frame.height == 110)
}

@Test func displayPlacementAlignsToBackingPixelsAndHandlesInvalidScale() {
    let geometry = IslandGeometry.layout(screenWidth: 1920, notchWidth: 0, notchHeight: 0,
                                         expanded: true, contentHeight: 72.3)
    let rect = CGRect(x: 0.3, y: 0.3, width: 1920.3, height: 1080.3)
    let retina = DisplayPlacementPolicy.frame(screenFrame: rect, visibleFrame: rect,
                                              geometry: geometry, backingScale: 2)
    #expect(retina.minX * 2 == (retina.minX * 2).rounded())
    #expect(retina.minY * 2 == (retina.minY * 2).rounded())
    #expect(retina.height * 2 == (retina.height * 2).rounded())
    let fallback = DisplayPlacementPolicy.frame(screenFrame: rect, visibleFrame: rect,
                                                geometry: geometry, backingScale: .nan)
    #expect(fallback.minX.isFinite && fallback.minY.isFinite)
}
