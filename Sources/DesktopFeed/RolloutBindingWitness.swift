import Darwin
import Foundation

/// A short-lived descriptor used to prove an otherwise unjoined history row.
/// Neither a recent timestamp nor a matching title establishes a binding.
final class RolloutBindingFile {
    struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ value: stat) {
            device = value.st_dev
            inode = value.st_ino
            size = value.st_size
            modifiedSeconds = value.st_mtimespec.tv_sec
            modifiedNanoseconds = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec
            changedNanoseconds = value.st_ctimespec.tv_nsec
        }
    }

    private let descriptor: Int32
    private let sourcePath: String
    private let canonicalPath: String
    let identity: Identity
    private(set) var bytesRead = 0
    private(set) var headerStateConfirmed = false
    private let budget: Int
    var size: UInt64 { UInt64(identity.size) }
    var remainingBytes: Int { max(0, budget - bytesRead) }

    init(path: String, home: URL, budget: Int = RolloutJSONLProjection.readBudget) throws {
        guard budget > 0, budget <= RolloutJSONLProjection.readBudget else { throw FeedError.oversized }
        self.budget = budget
        let allowed = try Self.resolve(home.appendingPathComponent("sessions", isDirectory: true).path)
        let requested = try Self.resolve(path)
        sourcePath = path
        canonicalPath = requested
        let prefix = allowed + "/"
        guard requested.hasPrefix(prefix) else { throw FeedError.invalidRollout }
        // Open every component relative to the preceding descriptor. Resolving
        // a path and then opening it by name alone would leave a replacement race.
        var directory = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else { throw FeedError.invalidRollout }
        do {
            let components = requested.split(separator: "/").map(String.init)
            for (index, component) in components.enumerated() {
                let last = index == components.count - 1
                let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (last ? O_NONBLOCK : O_DIRECTORY)
                let next = component.withCString { openat(directory, $0, flags) }
                guard next >= 0 else { throw FeedError.invalidRollout }
                close(directory)
                directory = next
            }
            var value = stat()
            guard fstat(directory, &value) == 0, (value.st_mode & S_IFMT) == S_IFREG,
                  value.st_size >= 0 else { throw FeedError.invalidRollout }
            descriptor = directory
            identity = Identity(value)
        } catch {
            close(directory)
            throw error
        }
    }

    deinit { close(descriptor) }

    func requireUnchanged() throws {
        var value = stat()
        var named = stat()
        guard fstat(descriptor, &value) == 0, Identity(value) == identity,
              (try? Self.resolve(sourcePath)) == canonicalPath,
              lstat(canonicalPath, &named) == 0, Identity(named) == identity else { throw FeedError.invalidRollout }
    }

    private static func resolve(_ path: String) throws -> String {
        // Foundation may preserve the macOS /var alias. The descriptor walk
        // needs the actual canonical components so O_NOFOLLOW remains strict.
        guard !path.utf8.contains(0), let resolved = realpath(path, nil) else { throw FeedError.invalidRollout }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    func read(at offset: UInt64, maximumBytes: Int) throws -> Data {
        guard offset <= UInt64(Int64.max), maximumBytes >= 0 else { throw FeedError.invalidRollout }
        let count = min(maximumBytes, remainingBytes)
        guard count > 0 else { return Data() }
        var data = Data(count: count)
        let length: Int = try data.withUnsafeMutableBytes { buffer in
            while true {
                let result = pread(descriptor, buffer.baseAddress, count, off_t(offset))
                if result < 0, errno == EINTR { continue }
                guard result >= 0 else { throw FeedError.invalidRollout }
                return result
            }
        }
        bytesRead += length
        data.count = length
        return data
    }

    /// Exact, complete records from this descriptor are the only witnesses.
    /// A caller must still establish uniqueness among eligible root sessions.
    func verifies(stateID: String, turnID: String, offset: UInt64) throws -> Bool {
        headerStateConfirmed = false
        guard !stateID.isEmpty, stateID.utf8.count <= 512,
              !turnID.isEmpty, turnID.utf8.count <= 512,
              offset > 0, offset < size else { return false }
        let headerBytes = try read(at: 0, maximumBytes: 65_536)
        guard let headerEnd = headerBytes.firstIndex(of: 10) else { throw FeedError.oversized }
        let header = try Self.decode(Data(headerBytes[..<headerEnd]))
        guard header.type == "session_meta", header.payload?.id == stateID else { return false }
        headerStateConfirmed = true
        guard try read(at: offset - 1, maximumBytes: 1) == Data([10]) else { return false }
        let eventBytes = try read(at: offset, maximumBytes: 65_536)
        guard let eventEnd = eventBytes.firstIndex(of: 10) else { throw FeedError.oversized }
        let event = try Self.decode(Data(eventBytes[..<eventEnd]))
        try requireUnchanged()
        return event.type == "event_msg" && event.payload?.type == "task_started"
            && event.payload?.turn_id == turnID
    }

    private struct Envelope: Decodable {
        let type: String?
        let payload: Payload?
        struct Payload: Decodable {
            let type: String?
            let id: String?
            let turn_id: String?
        }
    }

    private static func decode(_ bytes: Data) throws -> Envelope {
        do {
            return try JSONDecoder().decode(Envelope.self,
                from: RolloutJSONLProjection.bindingDocument(bytes))
        } catch let error as FeedError { throw error }
        catch { throw FeedError.invalidRollout }
    }
}
