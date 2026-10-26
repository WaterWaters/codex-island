import Darwin
import Foundation
import Testing
@testable import DesktopFeed

@Suite struct RolloutBindingWitnessTests {
    private let header = #"{"type":"session_meta","payload":{"id":"synthetic-state"}}"#
    private let event = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"synthetic-turn"}}"#

    private struct Fixture {
        let home: URL
        let path: URL
        let offset: UInt64
        func remove() { try? FileManager.default.removeItem(at: home) }
    }

    private func fixture(header: String? = nil, event: String? = nil,
                         eventNewline: Bool = true, tail: Data = Data()) throws -> Fixture {
        // Avoid /var or /tmp symlink aliases when exercising openat/O_NOFOLLOW.
        let base = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        let home = base.appendingPathComponent("island-binding-witness-\(UUID().uuidString)", isDirectory: true)
        let sessions = home.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let path = sessions.appendingPathComponent("synthetic.jsonl")
        let first = Data(((header ?? self.header) + "\n").utf8)
        var data = first
        data.append(Data((event ?? self.event).utf8))
        if eventNewline { data.append(10) }
        data.append(tail)
        do { try data.write(to: path) }
        catch { try? FileManager.default.removeItem(at: home); throw error }
        return Fixture(home: home, path: path, offset: UInt64(first.count))
    }

    private func rejectsBinding(_ file: RolloutBindingFile, offset: UInt64) {
        do {
            #expect(try !file.verifies(stateID: "synthetic-state", turnID: "synthetic-turn", offset: offset))
        } catch {
            // A malformed, incomplete or over-budget witness must fail closed.
        }
    }

    @Test func exactHeaderAndTaskRecordFromOneFileVerify() throws {
        let source = try fixture()
        defer { source.remove() }
        #expect(source.home.path.hasPrefix("/private/"))
        let file = try RolloutBindingFile(path: source.path.path, home: source.home)
        #expect(try file.verifies(stateID: "synthetic-state", turnID: "synthetic-turn", offset: source.offset))
        #expect(try !file.verifies(stateID: "different-state", turnID: "synthetic-turn", offset: source.offset))
        #expect(try !file.verifies(stateID: "synthetic-state", turnID: "different-turn", offset: source.offset))
        try file.requireUnchanged()
        #expect(file.bytesRead <= RolloutJSONLProjection.readBudget)
    }

    @Test func offsetsMustPointAtAnExactTaskRecordBoundary() throws {
        let unicodeHeader = #"{"type":"session_meta","payload":{"id":"synthetic-state"},"ignored":"猫"}"#
        let source = try fixture(header: unicodeHeader)
        defer { source.remove() }
        let bytes = Data((unicodeHeader + "\n").utf8)
        let utf8Start = try #require(bytes.firstIndex(of: 0xE7))
        let invalid: [UInt64] = [0, 1, UInt64(utf8Start + 1), source.offset - 1, source.offset + 1,
                                 UInt64(try Data(contentsOf: source.path).count), UInt64.max]
        for offset in invalid {
            let file = try RolloutBindingFile(path: source.path.path, home: source.home)
            rejectsBinding(file, offset: offset)
        }
        let file = try RolloutBindingFile(path: source.path.path, home: source.home)
        #expect(try file.verifies(stateID: "synthetic-state", turnID: "synthetic-turn", offset: source.offset))
    }

    @Test func wrongRecordKindsAndAmbiguousOrMalformedRecordsDoNotBind() throws {
        let cases: [(String, String)] = [
            (#"{"type":"other","payload":{"id":"synthetic-state"}}"#, event),
            (header, #"{"type":"response_item","payload":{"type":"task_started","turn_id":"synthetic-turn"}}"#),
            (header, #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"synthetic-turn"}}"#),
            (#"{"type":"session_meta","payload":{"id":"synthetic-state","id":"other"}}"#, event),
            (header, #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"synthetic-turn","turn_id":"other"}}"#),
            (#"{"type":"session_meta","payload":{"id":"synthetic-state"},"ignored":{"x":0,"x":1}}"#, event),
            (header, #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"synthetic-turn"},"ignored":{"x":0,"x":1}}"#),
            (#"{"type":"session_meta","payload":{"id":"synthetic-state"}"#, event),
            (header, #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"synthetic-turn"}"#),
            (header + " {}", event),
            (header, event + " {}"),
            (#"{"type":"session_meta","payload":{"id":"synthetic-state"},"ignored":"\uD800"}"#, event)
        ]
        for (first, second) in cases {
            let source = try fixture(header: first, event: second)
            defer { source.remove() }
            let file = try RolloutBindingFile(path: source.path.path, home: source.home)
            rejectsBinding(file, offset: source.offset)
        }
    }

    @Test func incompleteHeaderOrEventAndInvalidUTF8DoNotBind() throws {
        let noEventNewline = try fixture(eventNewline: false)
        defer { noEventNewline.remove() }
        let incompleteEvent = try RolloutBindingFile(path: noEventNewline.path.path, home: noEventNewline.home)
        rejectsBinding(incompleteEvent, offset: noEventNewline.offset)

        let noHeaderNewline = try fixture()
        defer { noHeaderNewline.remove() }
        try Data(header.utf8).write(to: noHeaderNewline.path)
        let incompleteHeader = try RolloutBindingFile(path: noHeaderNewline.path.path, home: noHeaderNewline.home)
        rejectsBinding(incompleteHeader, offset: 1)

        let invalid = try fixture()
        defer { invalid.remove() }
        var malformed = Data((header + "\n" + String(event.dropLast()) + ",\"ignored\":\"").utf8)
        malformed.append(contentsOf: [0xC0, 0xAF])
        malformed.append(Data("\"}\n".utf8))
        try malformed.write(to: invalid.path)
        let invalidFile = try RolloutBindingFile(path: invalid.path.path, home: invalid.home)
        rejectsBinding(invalidFile, offset: invalid.offset)
    }

    @Test func fifoDirectoryOutsidePathsAndSymlinkEscapesRejectWithoutBlocking() throws {
        let source = try fixture()
        defer { source.remove() }
        let sessions = source.path.deletingLastPathComponent()
        let fifo = sessions.appendingPathComponent("synthetic-fifo")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        let start = ContinuousClock.now
        #expect(throws: (any Error).self) { try RolloutBindingFile(path: fifo.path, home: source.home) }
        #expect(ContinuousClock.now - start < .seconds(2))
        #expect(throws: (any Error).self) { try RolloutBindingFile(path: sessions.path, home: source.home) }
        let outside = source.home.appendingPathComponent("outside.jsonl")
        try Data((header + "\n" + event + "\n").utf8).write(to: outside)
        #expect(throws: (any Error).self) { try RolloutBindingFile(path: outside.path, home: source.home) }
        let sibling = source.home.appendingPathComponent("sessions-sibling", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: false)
        let siblingFile = sibling.appendingPathComponent("synthetic.jsonl")
        try Data().write(to: siblingFile)
        #expect(throws: (any Error).self) { try RolloutBindingFile(path: siblingFile.path, home: source.home) }
        let escape = sessions.appendingPathComponent("escape.jsonl")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)
        #expect(throws: (any Error).self) { try RolloutBindingFile(path: escape.path, home: source.home) }
        let directoryEscape = sessions.appendingPathComponent("escape-dir", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: directoryEscape, withDestinationURL: source.home)
        #expect(throws: (any Error).self) {
            try RolloutBindingFile(path: directoryEscape.appendingPathComponent("outside.jsonl").path, home: source.home)
        }
    }

    @Test func replacementTruncationAndSameSizeModificationInvalidateIdentity() throws {
        for mutation in 0..<3 {
            let source = try fixture()
            defer { source.remove() }
            let file = try RolloutBindingFile(path: source.path.path, home: source.home)
            try file.requireUnchanged()
            switch mutation {
            case 0:
                try Data((header + "\n" + event + "\n").utf8).write(to: source.path, options: .atomic)
            case 1:
                let writer = try FileHandle(forWritingTo: source.path)
                defer { try? writer.close() }
                try writer.truncate(atOffset: file.size - 1)
            default:
                let writer = try FileHandle(forWritingTo: source.path)
                defer { try? writer.close() }
                try writer.write(contentsOf: Data("X".utf8))
                // Explicitly different metadata avoids relying on timing or
                // filesystem clock granularity for this same-size mutation.
                try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: source.path.path)
            }
            #expect(throws: (any Error).self) { try file.requireUnchanged() }
        }
    }

    @Test func sourceNameReplacedByAnEscapingSymlinkCannotKeepTheOldDescriptorValid() throws {
        let source = try fixture()
        defer { source.remove() }
        let file = try RolloutBindingFile(path: source.path.path, home: source.home)
        let outside = source.home.appendingPathComponent("outside.jsonl")
        try Data((header + "\n" + event + "\n").utf8).write(to: outside)
        try FileManager.default.removeItem(at: source.path)
        try FileManager.default.createSymbolicLink(at: source.path, withDestinationURL: outside)
        #expect(throws: (any Error).self) { try file.requireUnchanged() }
    }

    @Test func witnessAndSubsequentReadsShareOneCumulativeBudget() throws {
        let source = try fixture(tail: Data(repeating: 32, count: 400_000))
        defer { source.remove() }
        let file = try RolloutBindingFile(path: source.path.path, home: source.home)
        #expect(try file.verifies(stateID: "synthetic-state", turnID: "synthetic-turn", offset: source.offset))
        let usedByWitness = file.bytesRead
        #expect(usedByWitness > 0)
        #expect(file.remainingBytes == 262_144 - usedByWitness)
        let suffix = try file.read(at: source.offset, maximumBytes: 262_144)
        #expect(suffix.count == 262_144 - usedByWitness)
        #expect(file.bytesRead == 262_144)
        #expect(file.remainingBytes == 0)
        #expect(try file.read(at: 0, maximumBytes: 262_144).isEmpty)
        #expect(file.bytesRead == 262_144)
        try file.requireUnchanged()
        let tiny = try RolloutBindingFile(path: source.path.path, home: source.home, budget: 16)
        rejectsBinding(tiny, offset: source.offset)
        #expect(tiny.bytesRead <= 16)
        #expect(tiny.remainingBytes == 0)
        #expect(throws: (any Error).self) { try RolloutBindingFile(path: source.path.path, home: source.home, budget: 262_145) }
    }
}
