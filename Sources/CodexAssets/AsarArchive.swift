import Foundation
import CryptoKit

public enum AssetError: Error, Sendable {
    case invalidArchive, missingMember, oversized, integrityMismatch, incompatibleRenderer
}

/// Read selected packed members only. Never execute JS or follow unpacked links.
public struct AsarArchive: Sendable {
    private struct Entry: Decodable, Sendable {
        let files: [String: Entry]?
        let size: Int?
        let offset: String?
        let unpacked: Bool?
        let link: String?
        let integrity: Integrity?
    }
    private struct Integrity: Decodable, Sendable { let algorithm: String; let hash: String }
    private let root: Entry
    private let url: URL
    private let dataOffset: UInt64
    private let fileSize: UInt64

    public init(url: URL) throws {
        self.url = url
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        guard let prefix = try handle.read(upToCount: 16), prefix.count == 16 else { throw AssetError.invalidArchive }
        func word(_ offset: Int) -> UInt64 {
            (0..<4).reduce(0) { $0 | UInt64(prefix[offset + $1]) << ($1 * 8) }
        }
        let headerSize = word(4), jsonSize = word(12)
        guard word(0) == 4, headerSize >= 8, headerSize <= 16_777_216,
              jsonSize > 0, jsonSize <= headerSize - 8, 8 + headerSize <= fileSize,
              let data = try handle.read(upToCount: Int(jsonSize)), data.count == jsonSize else { throw AssetError.invalidArchive }
        dataOffset = 8 + headerSize
        root = try JSONDecoder().decode(Entry.self, from: data)
    }

    private func entry(_ path: String) throws -> Entry {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw AssetError.invalidArchive }
        var current = root
        for part in parts {
            guard let next = current.files?[String(part)], next.link == nil else { throw AssetError.missingMember }
            current = next
        }
        return current
    }

    public func members(in directory: String) throws -> [String] { try entry(directory).files?.keys.sorted() ?? [] }

    public func read(_ path: String, maximumSize: Int = 33_554_432) throws -> Data {
        let item = try entry(path)
        guard item.unpacked != true, let size = item.size, size >= 0,
              let offsetText = item.offset, let offset = UInt64(offsetText) else { throw AssetError.invalidArchive }
        guard size <= maximumSize else { throw AssetError.oversized }
        let (start, overflow) = dataOffset.addingReportingOverflow(offset)
        guard !overflow, start <= fileSize, UInt64(size) <= fileSize - start else { throw AssetError.invalidArchive }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: start)
        guard let data = try handle.read(upToCount: size), data.count == size else { throw AssetError.invalidArchive }
        if let integrity = item.integrity {
            guard integrity.algorithm == "SHA256",
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == integrity.hash.lowercased() else { throw AssetError.integrityMismatch }
        }
        return data
    }
}
