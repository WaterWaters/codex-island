import Foundation
import IslandCore

public struct PetDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let assetMember: String?
    public init(id: String, name: String, assetMember: String? = nil) {
        self.id = id; self.name = name; self.assetMember = assetMember
    }
    public static let systemIcon = Self(id: IslandSettings.fallbackPetID, name: "系统图标")
}

public struct CodexPetCatalog: Sendable {
    public let pets: [PetDescriptor]
    public let timing: PetTimingProfile
    public let version: String
}

/// Narrow, inert parsing of known literal layouts, not a JavaScript interpreter.
public enum PetRendererMetadata {
    static func matches(_ pattern: String, in text: String) throws -> [[String]] {
        let regex = try NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
        }
    }

    public static func timing(in text: String, version: String) throws -> PetTimingProfile {
        guard let idle = try matches(#"=([0-9]+),[\w$]+=\[(\{rowIndex:0,columnIndex:0,frameDurationMs:[0-9]+\}[^\]]{0,1500})\]"#, in: text).first,
              let multiplier = Int(idle[1]), (1...20).contains(multiplier) else { throw AssetError.incompatibleRenderer }
        let durations = try matches(#"frameDurationMs:([0-9]+)"#, in: idle[2]).compactMap { Int($0[1]) }
        // Bound the operands before multiplying: malformed metadata must throw,
        // rather than trap before PetTimingProfile can validate the result.
        guard durations.count == 6,
              durations.allSatisfy({ (1...(60_000 / multiplier)).contains($0) }) else {
            throw AssetError.incompatibleRenderer
        }
        var frames = [PetMotion.idle.rawValue: durations.map { $0 * multiplier }]
        let keys: [(PetMotion, String)] = [(.running, "running"), (.waiting, "waiting"), (.failed, "failed"),
                                          (.review, "review"), (.walkingLeft, "\"running-left\""), (.walkingRight, "\"running-right\"")]
        var factory: String?
        for (motion, key) in keys {
            let pattern = NSRegularExpression.escapedPattern(for: key) + #":([\w$]+)\("# + "\(motion.row),\(motion.frameCount)," + #"([0-9]+),([0-9]+)\)"#
            guard let values = try matches(pattern, in: text).first,
                  let regular = Int(values[2]), let last = Int(values[3]),
                  factory == nil || factory == values[1] else { throw AssetError.incompatibleRenderer }
            factory = values[1]
            frames[motion.rawValue] = Array(repeating: regular, count: motion.frameCount - 1) + [last]
        }
        // Check the four-argument factory's meaning, not just its call sites.
        let definition = "function " + NSRegularExpression.escapedPattern(for: factory ?? "") +
            #"\(([\w$]+),([\w$]+),([\w$]+),([\w$]+)\)\{return Array\.from\(\{length:\2\},\(([\w$]+),([\w$]+)\)=>\(\{columnIndex:\6,frameDurationMs:\6===\2-1\?\4:\3,rowIndex:\1\}\)\)\}"#
        guard try !matches(definition, in: text).isEmpty else { throw AssetError.incompatibleRenderer }
        return try PetTimingProfile(sourceVersion: version, frames: frames)
    }

    public static func pets(in text: String, assetNames: [String]) throws -> [PetDescriptor] {
        let literals = try matches(#"\{assetRef:`([a-z-]+)`,description:`[^`]*`,displayName:`([^`]+)`,id:`\1`,spriteVersionNumber:[12]\}"#, in: text)
        let pets = literals.compactMap { value -> PetDescriptor? in
            guard let member = assetNames.first(where: { $0.hasPrefix(value[1] + "-spritesheet-") && $0.hasSuffix(".webp") }) else { return nil }
            return PetDescriptor(id: value[1], name: value[2], assetMember: "webview/assets/" + member)
        }
        guard !pets.isEmpty, Set(pets.map(\.id)).count == pets.count else { throw AssetError.incompatibleRenderer }
        return pets
    }
}

public actor CodexPetReader {
    private var archive: AsarArchive?
    private var cached: CodexPetCatalog?
    private var signature: String?
    public init() {}

    public func catalog(applicationURL: URL, force: Bool = false) throws -> CodexPetCatalog {
        let url = applicationURL.appendingPathComponent("Contents/Resources/app.asar")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let version = Bundle(url: applicationURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let nextSignature = "\(url.path)|\(attributes[.modificationDate] ?? "")|\(attributes[.size] ?? "")|\(version)"
        if !force, signature == nextSignature, let cached { return cached }
        let nextArchive = try AsarArchive(url: url)
        let names = try nextArchive.members(in: "webview/assets")
        let candidates = names.filter { $0.hasPrefix("app-initial-") && $0.hasSuffix(".js") }
        guard candidates.count <= 8 else { throw AssetError.incompatibleRenderer }
        for member in candidates {
            let data = try nextArchive.read("webview/assets/" + member)
            guard let text = String(data: data, encoding: .utf8),
                  let timing = try? PetRendererMetadata.timing(in: text, version: version),
                  let pets = try? PetRendererMetadata.pets(in: text, assetNames: names) else { continue }
            let result = CodexPetCatalog(pets: pets, timing: timing, version: version)
            archive = nextArchive; cached = result; signature = nextSignature
            return result
        }
        throw AssetError.incompatibleRenderer
    }

    public func sprite(for pet: PetDescriptor) throws -> Data {
        guard let archive, let member = pet.assetMember else { throw AssetError.missingMember }
        return try archive.read(member, maximumSize: 16_777_216)
    }
}
