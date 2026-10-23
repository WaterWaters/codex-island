import Foundation
import ImageIO

public struct CustomPetCatalog: Sendable {
    public let pets: [PetDescriptor]
    public let preferredID: String?
    public let sourceUnavailable: Bool
}

/// Discovers local custom:/ legacy avatars and cloud pet_ artwork already
/// cached by Codex. Never reads credentials, makes requests or writes Codex.
enum CustomPetStore {
    static func catalog(home: URL, cacheDirectory: URL) -> CustomPetCatalog {
        var pets: [PetDescriptor] = []
        var unavailable = false
        for (directory, manifest) in [("pets", "pet.json"), ("avatars", "avatar.json")] {
            let root = home.appendingPathComponent(directory).resolvingSymlinksInPath()
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            do {
                let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                guard folders.count <= 256 else { throw AssetError.oversized }
                for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    guard let pet = try? localPet(folder: folder, root: root, manifest: manifest),
                          !pets.contains(where: { $0.id == pet.id }) else { continue }
                    pets.append(pet)
                }
            } catch { unavailable = true }
        }
        var preferred: String?
        do {
            let stateURL = home.appendingPathComponent(".codex-global-state.json")
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let state = try JSONDecoder().decode(GlobalState.self, from: LocalAssetFile.read(stateURL, maximumSize: 8_388_608))
                if let artwork = state.atoms?.artwork, !artwork.accountID.isEmpty, !artwork.userID.isEmpty {
                    guard artwork.pets.count <= 128 else { throw AssetError.oversized }
                    let indexed = artwork.pets.compactMap { pet -> (CloudArtwork, String)? in
                        guard pet.id.hasPrefix("pet_"), pet.id.utf8.count <= 200, (1...2).contains(pet.version),
                              let identity = CodexDiskCache.identity(in: pet.url),
                              let host = URL(string: identity)?.host, host.hasSuffix(".oaiusercontent.com") else { return nil }
                        return (pet, identity)
                    }
                    let cache = try CodexDiskCache(directory: cacheDirectory, artworkIdentities: Set(indexed.map(\.1)))
                    var names: [String: String] = [:]
                    for record in cache.records.filter({ CodexDiskCache.isCatalog($0.identity) }).prefix(16) {
                        guard let bytes = try? CodexDiskCache.catalogJSON(record),
                              let catalog = try? JSONDecoder().decode(CloudNames.self, from: bytes) else { continue }
                        for pet in catalog.pets where names[pet.id] == nil { names[pet.id] = pet.name }
                    }
                    for (pet, identity) in indexed where !pets.contains(where: { $0.id == pet.id }) {
                        let files = cache.records.filter { $0.identity == identity }.prefix(8).map(\.file)
                        guard !files.isEmpty else { unavailable = true; continue }
                        pets.insert(PetDescriptor(id: pet.id, name: cleanName(names[pet.id] ?? "自定义宠物"),
                            source: .codexCache(files: files, identity: identity, version: pet.version)), at: 0)
                    }
                    let key = String(decoding: try JSONEncoder().encode([artwork.accountID, artwork.userID]), as: UTF8.self)
                    preferred = state.atoms?.selections?[key]
                }
            }
        } catch { unavailable = true }
        return CustomPetCatalog(pets: pets, preferredID: preferred, sourceUnavailable: unavailable)
    }

    private static func localPet(folder: URL, root: URL, manifest: String) throws -> PetDescriptor {
        let directory = folder.resolvingSymlinksInPath()
        guard isInside(directory, root: root) else { throw AssetError.invalidArchive }
        let bytes = try LocalAssetFile.read(directory.appendingPathComponent(manifest), maximumSize: 65_536)
        let metadata = try JSONDecoder().decode(LocalManifest.self, from: bytes)
        let version = metadata.version ?? 1
        guard (1...2).contains(version), !metadata.path.hasPrefix("/"), !metadata.path.utf8.contains(0) else {
            throw AssetError.incompatibleRenderer
        }
        let image = directory.appendingPathComponent(metadata.path).resolvingSymlinksInPath()
        guard isInside(image, root: directory), folder.lastPathComponent.utf8.count <= 190 else { throw AssetError.invalidArchive }
        return PetDescriptor(id: "custom:" + folder.lastPathComponent,
                             name: cleanName(metadata.name ?? metadata.id ?? folder.lastPathComponent),
                             source: .localFile(image: image, root: directory, version: version))
    }

    static func sprite(for pet: PetDescriptor) throws -> Data {
        switch pet.source {
        case .localFile(let image, let root, let version):
            let resolved = image.resolvingSymlinksInPath()
            guard isInside(resolved, root: root) else { throw AssetError.invalidArchive }
            let bytes = try LocalAssetFile.read(resolved, maximumSize: 16_777_216)
            try validate(bytes, version: version)
            return bytes
        case .codexCache(let files, let identity, let version):
            for file in files {
                guard let result = try? CodexDiskCache.read(.init(file: file, identity: identity), maximumBodySize: 16_777_216),
                      (try? validate(result.body, version: version)) != nil else { continue }
                return result.body
            }
            throw AssetError.missingMember
        default: throw AssetError.missingMember
        }
    }

    private static func validate(_ data: Data, version: Int) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyPixelWidth] as? Int == 1536,
              properties[kCGImagePropertyPixelHeight] as? Int == (version == 1 ? 1872 : 2288) else {
            throw AssetError.incompatibleRenderer
        }
    }

    private static func isInside(_ url: URL, root: URL) -> Bool { url.path.hasPrefix(root.path + "/") }
    private static func cleanName(_ name: String) -> String {
        let value = name.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return value.isEmpty ? "自定义宠物" : String(value.prefix(100))
    }

    private struct LocalManifest: Decodable {
        let id: String?
        let name: String?
        let version: Int?
        let path: String
        enum CodingKeys: String, CodingKey {
            case id, name = "displayName", version = "spriteVersionNumber", path = "spritesheetPath"
        }
    }
    private struct CloudNames: Decodable {
        let pets: [Pet]
        struct Pet: Decodable { let id: String; let name: String }
    }
    private struct GlobalState: Decodable {
        let atoms: Atoms?
        enum CodingKeys: String, CodingKey { case atoms = "electron-persisted-atom-state" }
    }
    private struct Atoms: Decodable {
        let artwork: Artwork?
        let selections: [String: String]?
        enum CodingKeys: String, CodingKey {
            case artwork = "cloud-pet-artwork-cache", selections = "last-observed-cloud-pet-selection-v1"
        }
    }
    private struct Artwork: Decodable {
        let accountID: String
        let userID: String
        let pets: [CloudArtwork]
        enum CodingKeys: String, CodingKey { case accountID = "accountId", userID = "userId", pets }
    }
    private struct CloudArtwork: Decodable {
        let id: String
        let version: Int
        let url: String
        enum CodingKeys: String, CodingKey { case id, version = "spriteVersionNumber", url = "spritesheetUrl" }
    }
}
