import Compression
import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import Testing
import zlib
@testable import CodexAssets

private struct PetFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("island-pets-\(UUID().uuidString)")
    var home: URL { root.appendingPathComponent("home") }
    var cache: URL { root.appendingPathComponent("cache") }
    let identity = "https://fixture.oaiusercontent.com/pet/artwork/raw"

    init() throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }

    func image(height: Int = 2288) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 1536, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.7, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 40, y: 40, width: 80, height: 100))
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    func local(slug: String = "fixture", path: String = "pet.png", legacy: Bool = false, version: Int = 2) throws -> URL {
        let folder = home.appendingPathComponent(legacy ? "avatars" : "pets").appendingPathComponent(slug)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json: [String: Any] = ["displayName": "  测试\n宠物  ", "spriteVersionNumber": version, "spritesheetPath": path]
        try JSONSerialization.data(withJSONObject: json).write(to: folder.appendingPathComponent(legacy ? "avatar.json" : "pet.json"))
        return folder
    }

    func cloud() throws {
        let key = String(decoding: try JSONEncoder().encode(["fixture-account", "fixture-user"]), as: UTF8.self)
        let json: [String: Any] = ["electron-persisted-atom-state": [
            "cloud-pet-artwork-cache": ["accountId": "fixture-account", "userId": "fixture-user", "pets": [
                ["id": "pet_fixture", "spriteVersionNumber": 2, "spritesheetUrl": identity]
            ]], "last-observed-cloud-pet-selection-v1": [key: "pet_fixture"]
        ]]
        try JSONSerialization.data(withJSONObject: json).write(to: home.appendingPathComponent(".codex-global-state.json"))
    }

    @discardableResult func entry(_ index: Int, url: String, body: Data, headers: Data = Data("content-type:image/png".utf8)) throws -> URL {
        let key = Data(("fixture-cache-key " + url).utf8)
        var data = Data()
        func word(_ value: UInt64, bytes: Int = 4) {
            for offset in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (offset * 8))) }
        }
        func footer(_ content: Data, flags: UInt64, size: Int = 0) {
            word(0xf4fa6f45970d41d8, bytes: 8); word(flags)
            word(UInt64(content.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) }))
            word(UInt64(size)); word(0)
        }
        word(0xfcfb6d1ba7725c30, bytes: 8); word(5); word(UInt64(key.count)); word(0); word(0)
        data.append(key); data.append(body); footer(body, flags: 1)
        data.append(headers); data.append(contentsOf: SHA256.hash(data: key)); footer(headers, flags: 3, size: headers.count)
        let file = cache.appendingPathComponent(String(format: "%016x_0", index))
        try data.write(to: file)
        return file
    }
}

@Test func localAndLegacyPetsLoadWithoutAnInstalledApplication() async throws {
    let fixture = try PetFixture(); defer { fixture.remove() }
    let folder = try fixture.local()
    let bytes = try fixture.image()
    try bytes.write(to: folder.appendingPathComponent("pet.png"))
    let legacy = try fixture.local(slug: "legacy", legacy: true, version: 1)
    try fixture.image(height: 1872).write(to: legacy.appendingPathComponent("pet.png"))
    let reader = CodexPetReader()
    let catalog = await reader.customCatalog(home: fixture.home, cacheDirectory: fixture.cache)
    #expect(Set(catalog.pets.map(\.id)) == ["custom:fixture", "custom:legacy"])
    #expect(catalog.pets.allSatisfy { $0.name == "测试 宠物" })
    #expect(!catalog.sourceUnavailable)
    for pet in catalog.pets { #expect(try await reader.sprite(for: pet).count > 1000) }
}

@Test func escapedManifestsAndSymlinkedFoldersAreExcluded() throws {
    let fixture = try PetFixture(); defer { fixture.remove() }
    _ = try fixture.local(slug: "escape", path: "../../outside.png")
    _ = try fixture.local(slug: "absolute", path: "/tmp/outside.png")
    let outside = fixture.root.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: fixture.home.appendingPathComponent("pets/link"), withDestinationURL: outside)
    #expect(CustomPetStore.catalog(home: fixture.home, cacheDirectory: fixture.cache).pets.isEmpty)
}

@Test func localImagesRejectWrongDimensionsPipesAndPostDiscoveryEscapes() throws {
    let fixture = try PetFixture(); defer { fixture.remove() }
    let folder = try fixture.local()
    let file = folder.appendingPathComponent("pet.png")
    let pet = try #require(CustomPetStore.catalog(home: fixture.home, cacheDirectory: fixture.cache).pets.first)
    try Data("invalid image".utf8).write(to: file)
    #expect(throws: AssetError.self) { try CustomPetStore.sprite(for: pet) }
    try fixture.image(height: 1872).write(to: file)
    #expect(throws: AssetError.incompatibleRenderer) { try CustomPetStore.sprite(for: pet) }
    try FileManager.default.removeItem(at: file)
    #expect(mkfifo(file.path, 0o600) == 0)
    #expect(throws: AssetError.self) { try CustomPetStore.sprite(for: pet) }
    try FileManager.default.removeItem(at: file)
    let outside = fixture.root.appendingPathComponent("outside.png")
    try fixture.image().write(to: outside)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
    #expect(throws: AssetError.self) { try CustomPetStore.sprite(for: pet) }
}

@Test func cloudPetsUseOnlyIndexedCachedArtworkAndNames() async throws {
    let fixture = try PetFixture(); defer { fixture.remove() }
    try fixture.cloud()
    let image = try fixture.image()
    try fixture.entry(1, url: fixture.identity + "?temporary=fixture", body: image)
    try fixture.entry(2, url: "https://fixture.oaiusercontent.com/other-account/raw", body: image)
    try fixture.entry(3, url: "https://chatgpt.com/backend-api/pets?limit=20", body: Data(#"{"pets":[{"id":"pet_fixture","name":"测试云宠物"},{"id":"pet_other","name":"Other"}]}"#.utf8))
    let reader = CodexPetReader()
    let catalog = await reader.customCatalog(home: fixture.home, cacheDirectory: fixture.cache)
    #expect(catalog.pets.count == 1)
    #expect(catalog.preferredID == "pet_fixture")
    let pet = try #require(catalog.pets.first)
    #expect(pet.name == "测试云宠物")
    #expect(try await reader.sprite(for: pet) == image)
    #expect(!catalog.sourceUnavailable)
}

@Test func cacheCorruptionAndReplacementCannotReturnUnrelatedPixels() throws {
    let fixture = try PetFixture(); defer { fixture.remove() }
    let file = try fixture.entry(1, url: fixture.identity, body: Data("pixels".utf8))
    let record = CodexDiskCache.Record(file: file, identity: fixture.identity)
    #expect(try CodexDiskCache.read(record, maximumBodySize: 100).body == Data("pixels".utf8))
    #expect(throws: AssetError.self) { try CodexDiskCache.read(record, maximumBodySize: 2) }
    var corrupt = try Data(contentsOf: file)
    corrupt[24 + Data(("fixture-cache-key " + fixture.identity).utf8).count] ^= 1
    try corrupt.write(to: file)
    #expect(throws: AssetError.integrityMismatch) { try CodexDiskCache.read(record, maximumBodySize: 100) }
    try fixture.entry(1, url: "https://fixture.oaiusercontent.com/unrelated", body: Data("pixels".utf8))
    #expect(throws: AssetError.self) { try CodexDiskCache.read(record, maximumBodySize: 100) }
    try Data(repeating: 0, count: 30).write(to: file)
    #expect(throws: AssetError.self) { try CodexDiskCache.read(record, maximumBodySize: 100) }
}

@Test func missingCloudCacheDoesNotHideLocalPetsOrCreatePlaceholderPets() throws {
    let fixture = try PetFixture(); defer { fixture.remove() }
    try fixture.cloud(); _ = try fixture.local()
    let catalog = CustomPetStore.catalog(home: fixture.home, cacheDirectory: fixture.cache)
    #expect(catalog.pets.map(\.id) == ["custom:fixture"])
    #expect(catalog.sourceUnavailable)
}

@Test func emptyBrotliCatalogIsRejectedAndCacheEntriesAreBounded() throws {
    let fixture = try PetFixture(); defer { fixture.remove() }
    let file = try fixture.entry(1, url: "https://chatgpt.com/backend-api/pets", body: Data(), headers: Data("content-encoding: br".utf8))
    #expect(throws: AssetError.self) { try CodexDiskCache.catalogJSON(.init(file: file, identity: "https://chatgpt.com/backend-api/pets")) }
    let oversized = fixture.cache.appendingPathComponent("0000000000000002_0")
    FileManager.default.createFile(atPath: oversized.path, contents: nil)
    let handle = try FileHandle(forWritingTo: oversized)
    try handle.truncate(atOffset: UInt64(CodexDiskCache.maximumFileSize + 1)); try handle.close()
    #expect(try CodexDiskCache(directory: fixture.cache, artworkIdentities: []).records.count == 1)
}

@Test func brotliPetNamesAreDecodedFromTheCachedResponse() throws {
    let fixture = try PetFixture(); defer { fixture.remove() }
    try fixture.cloud()
    try fixture.entry(1, url: fixture.identity, body: fixture.image())
    // Synthetic JSON compressed with the reference Brotli encoder.
    let body = try #require(Data(base64Encoded: "GzYA+EXdlqosG9KjpYpYvHAQlHtBOG9NBDJIIfnACWuc47BdUHXIALE+5dtTRsYBQtFtS1JECw=="))
    try fixture.entry(2, url: "https://chatgpt.com/backend-api/pets?limit=20", body: body, headers: Data("content-encoding: br".utf8))
    let catalog = CustomPetStore.catalog(home: fixture.home, cacheDirectory: fixture.cache)
    #expect(catalog.pets.first?.name == "Brotli fixture")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_ISLAND_TEST_PET_HOME"] != nil))
func installedCustomPetsCanBeDiscoveredAndDecodedWithoutCopyingThem() async throws {
    let home = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["CODEX_ISLAND_TEST_PET_HOME"]))
    let cache = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["CODEX_ISLAND_TEST_PET_CACHE"]))
    let reader = CodexPetReader()
    let catalog = await reader.customCatalog(home: home, cacheDirectory: cache)
    #expect(!catalog.pets.isEmpty)
    for pet in catalog.pets { #expect(try await reader.sprite(for: pet).count > 1000) }
}
