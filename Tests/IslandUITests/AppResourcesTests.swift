import Foundation
import Testing
@testable import CodexIsland

@MainActor @Test func packagedResourcesDoNotEvaluateTheGeneratedDevelopmentAccessor() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("packaged-resource-\(UUID().uuidString).app")
    defer { try? FileManager.default.removeItem(at: root) }
    let resources = root.appendingPathComponent("Contents/Resources")
    let packaged = resources.appendingPathComponent("CodexIsland_CodexIsland.bundle")
    try FileManager.default.createDirectory(at: packaged.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
    let info = ["CFBundleIdentifier": "dev.water.synthetic-packaged-resource", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: root.appendingPathComponent("Contents/Info.plist"))
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "dev.water.synthetic-resources"], format: .xml, options: 0)
        .write(to: packaged.appendingPathComponent("Contents/Info.plist"))
    let application = try #require(Bundle(url: root))
    var evaluatedDevelopment = false
    let actual = AppResources.resolve(in: application) {
        evaluatedDevelopment = true
        return .main
    }
    #expect(!evaluatedDevelopment)
    #expect(actual.bundleURL.standardizedFileURL == packaged.standardizedFileURL)
    #expect(try Options(arguments: ["--check-resources"]).permitsPersistentChanges == false)
}

@MainActor @Test func unpackagedExecutablesCanStillUseSwiftPMResources() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("development-resource-\(UUID().uuidString).bundle")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "dev.water.synthetic-development"], format: .xml, options: 0)
        .write(to: root.appendingPathComponent("Info.plist"))
    let application = try #require(Bundle(url: root))
    var evaluatedDevelopment = false
    let result = AppResources.resolve(in: application) {
        evaluatedDevelopment = true
        return .main
    }
    #expect(evaluatedDevelopment)
    #expect(result === Bundle.main)
}
