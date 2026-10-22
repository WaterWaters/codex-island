import Foundation
import CryptoKit
import Testing
import IslandCore
@testable import CodexAssets

private let renderer = #"""
function J$(e,t,n,r){return Array.from({length:t},(i,a)=>({columnIndex:a,frameDurationMs:a===t-1?r:n,rowIndex:e}))}
h6s=6,g6s=[{rowIndex:0,columnIndex:0,frameDurationMs:280},{rowIndex:0,columnIndex:1,frameDurationMs:110},{rowIndex:0,columnIndex:2,frameDurationMs:110},{rowIndex:0,columnIndex:3,frameDurationMs:140},{rowIndex:0,columnIndex:4,frameDurationMs:140},{rowIndex:0,columnIndex:5,frameDurationMs:320}],v={failed:J$(5,8,140,240),review:J$(8,6,150,280),running:J$(7,6,120,220),"running-left":J$(2,8,120,220),"running-right":J$(1,8,120,220),waiting:J$(6,6,150,260)};
var pets=[{assetRef:`codex`,description:`Companion`,displayName:`Codex`,id:`codex`,spriteVersionNumber:2}];
"""#

@Test func extractsSharedFrameTimingWithoutExecutingJavascript() throws {
    let profile = try PetRendererMetadata.timing(in: renderer, version: "test-version")
    #expect(profile.frames == PetTimingProfile.compatibility.frames)
    #expect(profile.sourceVersion == "test-version")
    let changed = try PetRendererMetadata.timing(in: renderer.replacingOccurrences(of: "running:J$(7,6,120,220)", with: "running:J$(7,6,160,300)"), version: "new")
    #expect(changed.duration(for: .running) == 1100)
}

@Test func malformedOrDriftedTimingsAreRejected() {
    #expect(throws: Error.self) { try PetRendererMetadata.timing(in: renderer.replacingOccurrences(of: "waiting:J$", with: "unknown:J$"), version: "x") }
    #expect(throws: Error.self) { try PetRendererMetadata.timing(in: renderer.replacingOccurrences(of: "120,220", with: "0,220"), version: "x") }
    #expect(throws: Error.self) { try PetRendererMetadata.timing(in: renderer.replacingOccurrences(of: "a===t-1?r:n", with: "r"), version: "x") }
}

@Test func overflowingAndOversizedIdleDurationsAreRejectedBeforeMultiplication() {
    for value in [String(Int.max), "10001", "0"] {
        let malformed = renderer.replacingOccurrences(of: "frameDurationMs:280", with: "frameDurationMs:" + value)
        #expect(throws: AssetError.incompatibleRenderer) {
            try PetRendererMetadata.timing(in: malformed, version: "malformed")
        }
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_ISLAND_TEST_APP"] != nil))
func installedCodexCatalogAndAllBuiltinAssetsAreReadable() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["CODEX_ISLAND_TEST_APP"])
    let reader = CodexPetReader()
    let catalog = try await reader.catalog(applicationURL: URL(fileURLWithPath: path))
    #expect(catalog.pets.count >= 9)
    #expect(catalog.timing.duration(for: .idle) > 0)
    for pet in catalog.pets {
        let bytes = try await reader.sprite(for: pet)
        #expect(bytes.count > 1000)
    }
}

@Test func catalogRequiresMatchingLocalAssets() throws {
    let pets = try PetRendererMetadata.pets(in: renderer, assetNames: ["codex-spritesheet-v6-test.webp"])
    #expect(pets.count == 1)
    #expect(pets[0].assetMember == "webview/assets/codex-spritesheet-v6-test.webp")
    #expect(throws: Error.self) { try PetRendererMetadata.pets(in: renderer, assetNames: ["unrelated.webp"]) }
}

private func archiveFixture(body: Data, hash: String? = nil) throws -> URL {
    var member: [String: Any] = ["size": body.count, "offset": "0"]
    if let hash { member["integrity"] = ["algorithm": "SHA256", "hash": hash] }
    let json = try JSONSerialization.data(withJSONObject: ["files": ["assets": ["files": ["pet.webp": member]]]])
    var header = Data()
    func word(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { header.append(contentsOf: $0) } }
    word(4); word(UInt32(json.count + 8)); word(UInt32(json.count + 4)); word(UInt32(json.count))
    header.append(json); header.append(body)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("island-asar-\(UUID().uuidString).asar")
    try header.write(to: path)
    return path
}

@Test func archiveReadsOnlyBoundedMembersAndVerifiesDigest() throws {
    let bytes = Data("pet pixels".utf8)
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    let url = try archiveFixture(body: bytes, hash: digest)
    defer { try? FileManager.default.removeItem(at: url) }
    let archive = try AsarArchive(url: url)
    #expect(try archive.members(in: "assets") == ["pet.webp"])
    #expect(try archive.read("assets/pet.webp") == bytes)
    #expect(throws: AssetError.self) { try archive.read("../assets/pet.webp") }
    #expect(throws: AssetError.self) { try archive.read("assets/pet.webp", maximumSize: 1) }
    #expect(throws: AssetError.self) { try archive.read("assets/missing.webp") }
}

@Test func corruptMemberAndTruncatedArchiveAreRejected() throws {
    let url = try archiveFixture(body: Data([1,2,3]), hash: String(repeating: "0", count: 64))
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: AssetError.self) { try AsarArchive(url: url).read("assets/pet.webp") }
    try Data([4,0]).write(to: url)
    #expect(throws: AssetError.self) { try AsarArchive(url: url) }
}
