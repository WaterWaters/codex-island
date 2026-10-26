import AppKit
import SwiftUI
import Testing
import IslandCore
import DesktopFeed
@testable import CodexIsland

@MainActor @Test func miniHitRegionPassesThroughCameraAndTransparentCorners() {
    let normal = IslandGeometry.layout(screenWidth: 1920, notchWidth: 0, notchHeight: 0,
                                       expanded: true, displayMode: .mini)
    #expect(IslandHitRegion.contains(CGPoint(x: 22, y: 11), geometry: normal))
    #expect(!IslandHitRegion.contains(.zero, geometry: normal))
    #expect(!IslandHitRegion.contains(CGPoint(x: 22, y: 23), geometry: normal))
    let notch = IslandGeometry.layout(screenWidth: 1512, notchWidth: 180, notchHeight: 32,
                                      expanded: true, displayMode: .mini)
    #expect(!IslandHitRegion.contains(CGPoint(x: 95, y: 15), geometry: notch))
    #expect(IslandHitRegion.contains(CGPoint(x: 2, y: 15), geometry: notch))
    #expect(IslandHitRegion.contains(CGPoint(x: 188, y: 15), geometry: notch))
    #expect(IslandHitRegion.contains(CGPoint(x: 95, y: 35), geometry: notch))
    #expect(!IslandHitRegion.contains(CGPoint(x: 1, y: 37), geometry: notch))
}

@MainActor @Test func miniModePreservesStatusAndPrivacyWithoutAnnouncingAnInvisiblePet() throws {
    let model = PreviewRenderer.sampleModel(state: .needsInput)
    model.preferences.values.displayMode = .mini
    model.sessionTitle = "PRIVATE-TITLE"
    model.preferences.values.hideSessionTitle = true
    model.isDemo = false
    model.isLocalFeed = true
    model.localFeedHealth = FeedHealth(caughtUp: false, degradedThreads: 1)
    let previous = L10n.shared.language
    defer { L10n.shared.configure(language: previous) }
    for language in [AppLanguage.en, .zhHans, .zhHant, .ja] {
        L10n.shared.configure(language: language)
        #expect(model.state == .needsInput && model.effectState == .needsInput)
        #expect(model.accessibilityDescription.contains(model.displayDetail))
        #expect(model.accessibilityDescription.contains(L10n.text("同步受限")))
        #expect(!model.accessibilityDescription.contains("PRIVATE-TITLE"))
        #expect(!model.accessibilityDescription.contains(L10n.format("accessibility.pet", model.pets.displayName)))
        #expect(L10n.value("settings.mode_mini") != "settings.mode_mini")
    }
    #expect(try Options(arguments: ["--demo", "running", "--mini"]).permitsPersistentChanges == false)
    #expect(try Options(arguments: ["--mini"]).mini)
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_ISLAND_TEST_RENDER_PREVIEWS"] == "1",
                         "Set CODEX_ISLAND_TEST_RENDER_PREVIEWS=1 on a Mac with working graphics"))
func miniGalleryRendersEightDistinctNativeStates() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directory = root.appendingPathComponent("local/mini-native-gallery")
    try PreviewRenderer.renderGallery(to: directory, displayMode: .mini)
    var images = Set<Data>()
    for state in PreviewRenderer.galleryStates {
        for display in ["notched", "standard"] {
            let data = try Data(contentsOf: directory.appendingPathComponent("mini-\(state.rawValue)-\(display).png"))
            let bitmap = try #require(NSBitmapImageRep(data: data))
            #expect(bitmap.pixelsWide == 1296 && bitmap.pixelsHigh > 500)
            images.insert(data)
        }
    }
    #expect(images.count == 8)
}
