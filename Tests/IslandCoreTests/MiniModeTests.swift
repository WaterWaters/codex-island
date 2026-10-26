import Foundation
import CoreGraphics
import Testing
@testable import IslandCore

@Test func miniPreferenceMigrationAndRoundTripPreserveFullAppearance() throws {
    for value in ["", #", "displayMode":"future""#, #", "displayMode":42"#] {
        let json = Data((#"{"selectedPetID":"synthetic-pet","contentHeight":106,"neonPrimary":"FD00FF""# + value + "}").utf8)
        let settings = try JSONDecoder().decode(IslandSettings.self, from: json).sanitized()
        #expect(settings.displayMode == .full)
        #expect(settings.selectedPetID == "synthetic-pet" && settings.contentHeight == 106)
        #expect(settings.neonPrimary == "FD00FF")
    }
    var settings = IslandSettings()
    settings.selectedPetID = "synthetic-pet"
    settings.contentHeight = 106
    settings.displayMode = .mini
    settings.applyPreset(.quiet)
    let decoded = try JSONDecoder().decode(IslandSettings.self, from: JSONEncoder().encode(settings)).sanitized()
    #expect(decoded == settings)
    #expect(decoded.displayMode == .mini && decoded.contentHeight == 106)
}

@Test func miniGeometryAdaptsToCutoutWithoutUsingFullModeHeight() {
    for height in [60.0, 140] {
        let normal = IslandGeometry.layout(screenWidth: 1920, notchWidth: 0, notchHeight: 0,
                                           expanded: true, contentHeight: height, displayMode: .mini)
        #expect(normal.width == 44 && normal.height == 22 && !normal.hasNotch)
        for (width, depth) in [(180.0, 32.0), (214, 37), (163.5, 28.5)] {
            let notch = IslandGeometry.layout(screenWidth: 1512, notchWidth: width, notchHeight: depth,
                                              expanded: true, contentHeight: height, displayMode: .mini)
            #expect(notch.width == width + 10 && notch.height == depth + 6)
            #expect(notch.notchWidth == width && notch.notchHeight == depth && notch.hasNotch)
        }
    }
    let invalid = IslandGeometry.layout(screenWidth: 1920, notchWidth: .nan, notchHeight: .infinity,
                                        expanded: true, displayMode: .mini)
    #expect(!invalid.hasNotch && invalid.width == 44 && invalid.height == 22)
}

@Test func miniPlacementAttachesToPhysicalTopAcrossMenuBarAndScaleChanges() {
    let normal = IslandGeometry.layout(screenWidth: 1920, notchWidth: 0, notchHeight: 0,
                                       expanded: true, displayMode: .mini)
    let screen = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
    for scale in [1.0, 2.0] {
        for menuHeight in [0.0, 24, 38] {
            let visible = CGRect(x: -1920, y: -1080, width: 1920, height: 1080 - menuHeight)
            let frame = DisplayPlacementPolicy.frame(screenFrame: screen, visibleFrame: visible,
                                                      geometry: normal, backingScale: scale)
            #expect(frame.maxY == 0 && frame.midX == -960)
            #expect(frame.width == 44 && frame.height == 22)
        }
    }
}

@Test func cutoutResolutionUsesGlobalAreasAndRejectsIncompleteOrContradictoryMetrics() throws {
    let screen = CGRect(x: -1600, y: 100, width: 1600, height: 1000)
    let left = CGRect(x: -1600, y: 1068, width: 680, height: 32)
    let right = CGRect(x: -720, y: 1068, width: 720, height: 32)
    let cutout = try #require(DisplayCutout.resolve(screenFrame: screen, safeAreaTop: 32, leftArea: left, rightArea: right))
    #expect(cutout.width == 200 && cutout.height == 32 && cutout.centerX == -820)
    let geometry = IslandGeometry.layout(screenWidth: 1600, notchWidth: cutout.width, notchHeight: cutout.height,
                                         expanded: true, displayMode: .mini)
    let frame = DisplayPlacementPolicy.frame(screenFrame: screen, visibleFrame: screen, geometry: geometry,
                                              backingScale: 2, notchCenterX: cutout.centerX)
    #expect(frame.midX == -820 && frame.maxY == 1100)
    #expect(frame.width == 210 && frame.height == 38)
    #expect(DisplayCutout.resolve(screenFrame: screen, safeAreaTop: 0, leftArea: left, rightArea: right) == nil)
    #expect(DisplayCutout.resolve(screenFrame: screen, safeAreaTop: .nan, leftArea: left, rightArea: right) == nil)
    #expect(DisplayCutout.resolve(screenFrame: screen, safeAreaTop: 32, leftArea: nil, rightArea: right) == nil)
    #expect(DisplayCutout.resolve(screenFrame: screen, safeAreaTop: 32, leftArea: left, rightArea: left) == nil)
    #expect(DisplayCutout.resolve(screenFrame: screen, safeAreaTop: 32, leftArea: left.offsetBy(dx: 0, dy: -32), rightArea: right) == nil)
}
