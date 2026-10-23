import CoreGraphics
import Foundation
import ImageIO
import IslandCore
import Testing
@testable import CodexIsland

@MainActor @Test func customSelectionSurvivesResyncRestartAndTemporaryAssetFailures() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("island-library-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("pets/fixture")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(#"{"displayName":"Fixture","spriteVersionNumber":2,"spritesheetPath":"pet.png"}"#.utf8)
        .write(to: folder.appendingPathComponent("pet.json"))
    let context = try #require(CGContext(data: nil, width: 1536, height: 2288, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let bytes = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    let image = folder.appendingPathComponent("pet.png")
    try (bytes as Data).write(to: image)
    let library = PetLibrary(home: root, cacheDirectory: root)
    #expect(await library.synchronize(applicationURL: nil, selectedID: "custom:fixture", force: false))
    let atlas = try #require(library.atlas)
    #expect(library.pets.map(\.id) == ["custom:fixture"])
    #expect(library.displayName == "Fixture")
    let suite = "island-custom-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    IslandPreferences(defaults: defaults).values.selectedPetID = library.selectedID
    let restored = PetLibrary(home: root, cacheDirectory: root)
    #expect(await restored.synchronize(applicationURL: nil, selectedID: IslandPreferences(defaults: defaults).values.selectedPetID, force: false))
    #expect(restored.atlas != nil && restored.selectedID == "custom:fixture")
    try Data("damaged".utf8).write(to: image)
    #expect(!(await library.synchronize(applicationURL: nil, selectedID: "custom:fixture", force: true)))
    #expect(library.atlas === atlas && library.selectedID == "custom:fixture")
    try FileManager.default.removeItem(at: folder)
    #expect(!(await library.synchronize(applicationURL: nil, selectedID: "custom:fixture", force: true)))
    #expect(library.atlas === atlas && library.displayName == "Fixture")
    #expect(library.pets.isEmpty)
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_ISLAND_TEST_PET_HOME"] != nil))
func installedCustomPetAppearsInThePickerAndProducesAnimationFrames() async throws {
    let home = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["CODEX_ISLAND_TEST_PET_HOME"]))
    let cache = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["CODEX_ISLAND_TEST_PET_CACHE"]))
    let library = PetLibrary(home: home, cacheDirectory: cache)
    _ = await library.synchronize(applicationURL: nil, selectedID: IslandSettings.defaultPetID, force: true)
    let custom = try #require(library.pets.first { $0.id.hasPrefix("pet_") || $0.id.hasPrefix("custom:") })
    #expect(await library.synchronize(applicationURL: nil, selectedID: custom.id, force: false))
    #expect(library.selectedID == custom.id)
    #expect(library.atlas?.frame(motion: .running, index: 0) != nil)
    #expect(!library.pets.contains { $0.id == "system-icon" })
}
