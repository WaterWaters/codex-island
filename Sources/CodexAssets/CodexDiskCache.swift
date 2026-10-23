import Compression
import CryptoKit
import Darwin
import Foundation
import zlib

/// Bounded, read-only access to regular local files. In particular a named
/// pipe or a symlink substituted for a cache entry must not block or escape.
enum LocalAssetFile {
    static func open(_ url: URL, maximumSize: Int) throws -> FileHandle {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw AssetError.missingMember }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size >= 0, info.st_size <= maximumSize else {
            try? handle.close()
            throw AssetError.oversized
        }
        return handle
    }

    static func read(_ url: URL, maximumSize: Int) throws -> Data {
        let handle = try open(url, maximumSize: maximumSize)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: maximumSize + 1) ?? Data()
        guard bytes.count <= maximumSize else { throw AssetError.oversized }
        return bytes
    }
}

/// Known Chromium Simple Cache v5 stream layout, not a general browser-data
/// reader. Only pet-catalog and explicitly indexed artwork keys are opened.
/// Format: chromium/src/net/disk_cache/simple/simple_entry_format.h.
struct CodexDiskCache {
    struct Record: Equatable, Sendable {
        let file: URL
        let identity: String
    }
    let records: [Record]
    static let maximumFileSize = 18 * 1_048_576
    private static let initialMagic: UInt64 = 0xfcfb6d1ba7725c30
    private static let finalMagic: UInt64 = 0xf4fa6f45970d41d8

    init(directory: URL, artworkIdentities: Set<String>) throws {
        let root = directory.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: root.path) else { records = []; return }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.range(of: #"^[0-9a-f]{16}_0$"#, options: .regularExpression) != nil }
        guard files.count <= 4096 else { throw AssetError.oversized }
        var matches: [(Record, Date)] = []
        for file in files {
            guard let key = try? Self.readKey(file), let identity = Self.identity(in: key),
                  artworkIdentities.contains(identity) || Self.isCatalog(identity) else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            matches.append((Record(file: file, identity: identity), modified))
        }
        records = matches.sorted { $0.1 == $1.1 ? $0.0.file.lastPathComponent < $1.0.file.lastPathComponent : $0.1 > $1.1 }.map(\.0)
    }

    static func identity(in key: String) -> String? {
        guard let start = key.range(of: "https://", options: .backwards),
              let url = URLComponents(string: String(key[start.lowerBound...])),
              url.scheme == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        return "https://" + host + url.percentEncodedPath
    }

    static func isCatalog(_ identity: String) -> Bool {
        identity == "https://chatgpt.com/backend-api/pets"
    }

    private static func readKey(_ file: URL) throws -> String {
        let handle = try LocalAssetFile.open(file, maximumSize: maximumFileSize)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 24) ?? Data()
        guard header.count == 24, number(header, at: 0, bytes: 8) == initialMagic,
              number(header, at: 8) == 5, let length = number(header, at: 12), (1...16384).contains(length),
              let bytes = try handle.read(upToCount: Int(length)), bytes.count == length,
              let key = String(data: bytes, encoding: .utf8) else { throw AssetError.invalidArchive }
        return key
    }

    static func read(_ record: Record, maximumBodySize: Int) throws -> (body: Data, headers: Data) {
        let data = try LocalAssetFile.read(record.file, maximumSize: maximumFileSize)
        guard data.count >= 72, number(data, at: 0, bytes: 8) == initialMagic,
              number(data, at: 8) == 5, let length = number(data, at: 12), (1...16384).contains(length) else {
            throw AssetError.invalidArchive
        }
        let bodyStart = 24 + Int(length), eof0 = data.count - 24
        guard bodyStart <= eof0,
              let key = String(data: data.subdata(in: 24..<bodyStart), encoding: .utf8), identity(in: key) == record.identity,
              number(data, at: eof0, bytes: 8) == finalMagic,
              let flags0 = number(data, at: eof0 + 8), flags0 <= 3,
              let headerSize = number(data, at: eof0 + 16), headerSize <= 1_048_576 else { throw AssetError.invalidArchive }
        let keyHashSize = flags0 & 2 == 0 ? 0 : 32
        let headerEnd = eof0 - keyHashSize, headerStart = headerEnd - Int(headerSize), eof1 = headerStart - 24
        guard eof1 >= bodyStart, eof1 - bodyStart <= maximumBodySize,
              number(data, at: eof1, bytes: 8) == finalMagic,
              let flags1 = number(data, at: eof1 + 8), flags1 <= 1 else { throw AssetError.invalidArchive }
        let body = data.subdata(in: bodyStart..<eof1), headers = data.subdata(in: headerStart..<headerEnd)
        if keyHashSize > 0 {
            guard Data(SHA256.hash(data: Data(key.utf8))) == data.subdata(in: headerEnd..<eof0) else {
                throw AssetError.integrityMismatch
            }
        }
        for (bytes, eof, flags) in [(body, eof1, flags1), (headers, eof0, flags0)] where flags & 1 != 0 {
            let checksum = bytes.withUnsafeBytes { raw in
                crc32(0, raw.bindMemory(to: Bytef.self).baseAddress, uInt(raw.count))
            }
            guard number(data, at: eof + 12) == UInt64(checksum) else { throw AssetError.integrityMismatch }
        }
        return (body, headers)
    }

    static func catalogJSON(_ record: Record) throws -> Data {
        let (body, headers) = try read(record, maximumBodySize: 1_048_576)
        let metadata = String(decoding: headers, as: UTF8.self).lowercased()
        if metadata.contains("content-encoding:br") || metadata.contains("content-encoding: br") {
            guard !body.isEmpty else { throw AssetError.invalidArchive }
            var output = [UInt8](repeating: 0, count: 2_097_152)
            let count = output.withUnsafeMutableBufferPointer { destination in
                body.withUnsafeBytes { source in
                    compression_decode_buffer(destination.baseAddress!, destination.count,
                                              source.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_BROTLI)
                }
            }
            guard count > 0, count < output.count else { throw AssetError.invalidArchive }
            return Data(output.prefix(count))
        }
        return body
    }

    private static func number(_ data: Data, at offset: Int, bytes: Int = 4) -> UInt64? {
        guard offset >= 0, offset <= data.count, bytes <= data.count - offset else { return nil }
        return (0..<bytes).reduce(UInt64(0)) { $0 | UInt64(data[offset + $1]) << ($1 * 8) }
    }
}
