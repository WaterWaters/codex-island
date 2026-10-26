import Foundation

/// Validates every byte, but stores only the fields used by RolloutSignals.
/// No complete source line, tool output, question title or answer is retained.
struct RolloutJSONLProjection {
    static let readBudget = 262_144
    static let bindingDocumentBudget = 65_536
    private var parser = ProjectedJSONParser(rule: .event)
    private(set) var hasPartialRecord = false

    /// The standalone API accepts a single JSON document, including JSON
    /// whitespace and formatting newlines. Feed records remain strict JSONL.
    static func document(_ data: Data) throws -> Data {
        var parser = ProjectedJSONParser(rule: .event)
        for byte in data { try parser.consume(byte) }
        return try JSONEncoder().encode(parser.finish())
    }

    /// A single bounded identity witness, not a rollout event stream. The
    /// caller still proves record location, file identity and expected IDs.
    /// Every object's keys are checked, including discarded metadata objects.
    /// Decoded keys are limited to 512 bytes, 1024 per object and 2048 total;
    /// their retained bytes also stay beneath the 64 KiB document bound.
    static func bindingDocument(_ data: Data) throws -> Data {
        guard data.count <= bindingDocumentBudget else { throw FeedError.oversized }
        var parser = ProjectedJSONParser(rule: .binding, strictObjectKeys: true)
        for byte in data { try parser.consume(byte) }
        return try JSONEncoder().encode(parser.finish())
    }

    mutating func consume(_ data: Data, line: (Data) throws -> Void) throws {
        for byte in data {
            if byte == 10 {
                let value = try parser.finish()
                try line(try JSONEncoder().encode(value))
                parser = ProjectedJSONParser(rule: .event)
                hasPartialRecord = false
            } else {
                try parser.consume(byte)
                hasPartialRecord = true
            }
        }
    }

    // Testable accounting, independent of allocator / RSS noise. Fixed parser
    // stacks and at most one readBudget input buffer are additional overhead.
    var retainedBytes: Int { parser.liveRetainedBytes }
}

private indirect enum ProjectionRule: Sendable {
    case discard, object([String: ProjectionRule]), array(ProjectionRule, Int), shapeArray
    case string(Int), boolean, embedded(ProjectionRule), reply

    static let event: Self = .object([
        "type": .string(512),
        "payload": .object([
            "type": .string(512), "name": .string(512), "call_id": .string(512),
            "turn_id": .string(512), "role": .string(512),
            "arguments": .embedded(.object(["questions": .array(.object([:]), 32)])),
            "output": .embedded(.object(["accepted": .boolean])),
            "content": .array(.object(["type": .string(512), "text": .reply]), 1024)
        ])
    ])

    static let binding: Self = .object([
        "type": .string(512),
        "payload": .object([
            "type": .string(512), "id": .string(512), "turn_id": .string(512)
        ])
    ])

    var isDiscard: Bool { if case .discard = self { true } else { false } }
}

private indirect enum ProjectedJSON: Encodable {
    case null, number, string(String), boolean(Bool), object([String: ProjectedJSON]), array([ProjectedJSON])

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .number: try container.encode(0)
        case let .string(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        }
    }
}

private enum ProjectionFailure: Error { case malformed, ambiguous }

/// A small strict JSON recognizer: a bounded stack, finite number/literal
/// states, and scalar-by-scalar UTF-8 / UTF-16 escape validation. Ordinary
/// event projection discards unknown bodies without length-proportional
/// storage. Binding mode additionally keeps strictly bounded object key sets.
private struct ProjectedJSONParser {
    static let maximumDepth = 64
    static let maximumRetainedBytes = 1_048_576
    private static let maximumKeysPerObject = 1024
    private static let maximumDocumentKeys = 2048
    private static let maximumDocumentKeyBytes = 65_536
    private let rule: ProjectionRule
    private let strictObjectKeys: Bool
    private var documentKeys = 0
    private var documentKeyBytes = 0
    private var frames: [Frame] = []
    private var token: Token?
    private var result: ProjectedJSON?
    private(set) var retainedBytes = 0

    private struct Frame {
        enum Phase { case firstKey, key, colon, objectValue, objectComma, firstValue, value, arrayComma }
        let rule: ProjectionRule
        var phase: Phase
        var key: String?
        var seen = Set<String>()
        var object: [String: ProjectedJSON] = [:]
        var array: [ProjectedJSON] = []

        var nextRule: ProjectionRule {
            switch rule {
            case let .object(fields): key.flatMap { fields[$0] } ?? .discard
            case let .array(item, _): item
            default: .discard
            }
        }
    }

    private enum Token {
        case string(JSONStringToken, Bool)
        case number(NumberState, ProjectionRule)
        case literal([UInt8], Int, ProjectedJSON, ProjectionRule)
    }
    private enum NumberState {
        case minus, zero, integer, dot, fraction, exponent, exponentSign, exponentDigits
        var complete: Bool {
            switch self { case .zero, .integer, .fraction, .exponentDigits: true; default: false }
        }
        func next(_ byte: UInt8) -> Self? {
            switch (self, byte) {
            case (.minus, 48): .zero
            case (.minus, 49...57): .integer
            case (.integer, 48...57): .integer
            case (.zero, 46), (.integer, 46): .dot
            case (.dot, 48...57), (.fraction, 48...57): .fraction
            case (.zero, 69), (.zero, 101), (.integer, 69), (.integer, 101), (.fraction, 69), (.fraction, 101): .exponent
            case (.exponent, 43), (.exponent, 45): .exponentSign
            case (.exponent, 48...57), (.exponentSign, 48...57), (.exponentDigits, 48...57): .exponentDigits
            default: nil
            }
        }
    }

    init(rule: ProjectionRule, strictObjectKeys: Bool = false) {
        self.rule = rule
        self.strictObjectKeys = strictObjectKeys
    }

    var liveRetainedBytes: Int {
        if case let .string(string, _) = token { return retainedBytes + string.retainedBytes }
        return retainedBytes
    }

    mutating func consume(_ byte: UInt8) throws {
        if let current = token {
            switch current {
            case let .string(string, key):
                if try string.consume(byte) {
                    token = nil
                    if key { try acceptKey(string.key) }
                    else {
                        let value = string.value()
                        try accept(value, failure: string.failure)
                        if case let .string(text) = value { retainedBytes += text.utf8.count }
                    }
                    try checkBudget()
                } else {
                    guard retainedBytes + string.retainedBytes <= Self.maximumRetainedBytes else { throw FeedError.oversized }
                    token = .string(string, key)
                }
                return
            case let .number(state, selected):
                if let next = state.next(byte) { token = .number(next, selected); return }
                guard state.complete else { throw ProjectionFailure.malformed }
                token = nil
                try accept(.number)
                // Delimiter belongs to the enclosing container.
            case let .literal(bytes, index, value, selected):
                guard byte == bytes[index] else { throw ProjectionFailure.malformed }
                if index + 1 < bytes.count { token = .literal(bytes, index + 1, value, selected) }
                else {
                    token = nil
                    try accept(value)
                }
                return
            }
        }
        if Self.whitespace(byte) { return }
        guard let top = frames.last else {
            guard result == nil else { throw ProjectionFailure.malformed }
            try startValue(byte, selected: rule)
            return
        }
        switch top.phase {
        case .firstKey, .key:
            if byte == 125, top.phase == .firstKey { try closeObject(); return }
            guard byte == 34 else { throw ProjectionFailure.malformed }
            token = .string(JSONStringToken(key: true, rule: .discard, rejectOversizedKeys: strictObjectKeys), true)
        case .colon:
            guard byte == 58 else { throw ProjectionFailure.malformed }
            frames[frames.count - 1].phase = .objectValue
        case .objectValue, .value: try startValue(byte, selected: top.nextRule)
        case .firstValue:
            if byte == 93 { try closeArray(); return }
            try startValue(byte, selected: top.nextRule)
        case .objectComma:
            if byte == 125 { try closeObject() }
            else if byte == 44 { frames[frames.count - 1].phase = .key }
            else { throw ProjectionFailure.malformed }
        case .arrayComma:
            if byte == 93 { try closeArray() }
            else if byte == 44 { frames[frames.count - 1].phase = .value }
            else { throw ProjectionFailure.malformed }
        }
    }

    mutating func finish() throws -> ProjectedJSON {
        if case let .number(state, _) = token {
            guard state.complete else { throw ProjectionFailure.malformed }
            token = nil
            try accept(.number)
        }
        guard token == nil, frames.isEmpty, let result else { throw ProjectionFailure.malformed }
        return result
    }

    var isComplete: Bool { result != nil && frames.isEmpty && token == nil }

    private mutating func startValue(_ byte: UInt8, selected: ProjectionRule) throws {
        switch byte {
        case 123:
            frames.append(Frame(rule: selected.isDiscard || selected.isObject ? selected : .object([:]), phase: .firstKey))
        case 91:
            frames.append(Frame(rule: selected.isDiscard || selected.isArray ? selected : .shapeArray, phase: .firstValue))
        case 34:
            token = .string(JSONStringToken(key: false, rule: selected.isString ? selected : .discard), false)
        case 116: token = .literal(Array("true".utf8), 1, .boolean(true), selected)
        case 102: token = .literal(Array("false".utf8), 1, .boolean(false), selected)
        case 110: token = .literal(Array("null".utf8), 1, .null, selected)
        case 45: token = .number(.minus, selected)
        case 48: token = .number(.zero, selected)
        case 49...57: token = .number(.integer, selected)
        default: throw ProjectionFailure.malformed
        }
        guard frames.count <= Self.maximumDepth else { throw FeedError.oversized }
    }

    private mutating func acceptKey(_ key: String?) throws {
        let index = frames.count - 1
        if strictObjectKeys {
            guard let key, frames[index].seen.count < Self.maximumKeysPerObject,
                  documentKeys < Self.maximumDocumentKeys else { throw FeedError.oversized }
            guard frames[index].seen.insert(key).inserted else { throw ProjectionFailure.ambiguous }
            documentKeys += 1
            documentKeyBytes += key.utf8.count
            guard documentKeyBytes <= Self.maximumDocumentKeyBytes else { throw FeedError.oversized }
        }
        if let key, case let .object(fields) = frames[index].rule, fields[key] != nil {
            if !strictObjectKeys {
                guard frames[index].seen.insert(key).inserted else { throw ProjectionFailure.ambiguous }
            }
            frames[index].key = key
        } else { frames[index].key = nil }
        frames[index].phase = .colon
    }

    private mutating func accept(_ value: ProjectedJSON, failure: FeedError? = nil) throws {
        guard !frames.isEmpty else { result = value; return }
        let index = frames.count - 1
        switch frames[index].phase {
        case .objectValue:
            if let key = frames[index].key {
                frames[index].object[key] = value
                if let failure { frames[index].object["_island_projection_\(key)_failure"] = .string(failure.rawValue) }
            }
            frames[index].key = nil
            frames[index].phase = .objectComma
        case .firstValue, .value:
            if case let .array(_, maximum) = frames[index].rule {
                guard frames[index].array.count < maximum else { throw FeedError.oversized }
                frames[index].array.append(value)
                retainedBytes += 8
                try checkBudget()
            }
            frames[index].phase = .arrayComma
        default: throw ProjectionFailure.malformed
        }
    }

    private mutating func closeObject() throws {
        let top = frames.removeLast()
        try accept(top.rule.isDiscard ? .null : .object(top.object))
    }
    private mutating func closeArray() throws {
        let top = frames.removeLast()
        try accept(top.rule.isDiscard ? .null : .array(top.array))
    }
    private func checkBudget() throws {
        guard retainedBytes <= Self.maximumRetainedBytes else { throw FeedError.oversized }
    }
    static func whitespace(_ byte: UInt8) -> Bool { byte == 32 || byte == 9 || byte == 10 || byte == 13 }
}

private extension ProjectionRule {
    var isObject: Bool { if case .object = self { true } else { false } }
    var isArray: Bool { switch self { case .array, .shapeArray: true; default: false } }
    var isString: Bool {
        switch self { case .string, .embedded, .reply: true; default: false }
    }
}

/// The only recursively allocated parsers are the two known JSON-in-string
/// layers. Arbitrary strings under ignored fields never allocate a parser.
private final class EmbeddedProjection {
    var parser: ProjectedJSONParser
    var invalid = false
    init(rule: ProjectionRule) { parser = ProjectedJSONParser(rule: rule) }
    func consume(_ bytes: [UInt8]) throws {
        guard !invalid else { return }
        do { for byte in bytes { try parser.consume(byte) } }
        catch ProjectionFailure.malformed { invalid = true }
    }
    func value() throws -> String {
        guard !invalid else { return "" }
        do { return String(decoding: try JSONEncoder().encode(parser.finish()), as: UTF8.self) }
        catch ProjectionFailure.malformed { return "" }
    }
}

private final class ReplyProjection {
    static let start = Array("<send_user_message_question_reply>".utf8)
    static let end = Array("</send_user_message_question_reply>".utf8)
    private var prefix = 0
    private var suffix = 0
    private var invalid = false
    private var parser = ProjectedJSONParser(rule: .array(.object(["questionItemId": .string(4096)]), 1024))

    func consume(_ bytes: [UInt8]) throws {
        guard !invalid else { return }
        if prefix == 0, String(decoding: bytes, as: UTF8.self).unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) { return }
        for byte in bytes {
            if prefix < Self.start.count {
                guard byte == Self.start[prefix] else { invalid = true; return }
                prefix += 1
            } else if !parser.isComplete {
                do { try parser.consume(byte) }
                catch ProjectionFailure.malformed { invalid = true; return }
            } else if suffix == 0 && ProjectedJSONParser.whitespace(byte) { continue }
            else if suffix < Self.end.count {
                guard byte == Self.end[suffix] else { invalid = true; return }
                suffix += 1
            } else {
                // Trailing Unicode whitespace is checked scalar-wise below.
                guard String(decoding: bytes, as: UTF8.self).unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) else { invalid = true; return }
                return
            }
        }
    }

    func value() throws -> String {
        guard !invalid, prefix == Self.start.count, suffix == Self.end.count else { return "" }
        return String(decoding: Self.start, as: UTF8.self)
            + String(decoding: try JSONEncoder().encode(parser.finish()), as: UTF8.self)
            + String(decoding: Self.end, as: UTF8.self)
    }
    var retainedBytes: Int { parser.liveRetainedBytes }
}

private final class JSONStringToken {
    private enum Escape { case raw, escaped, unicode(Int, UInt32), lowSlash, lowU, lowUnicode(Int, UInt32) }
    private let isKey: Bool
    private let rule: ProjectionRule
    private let rejectOversizedKeys: Bool
    private var escape = Escape.raw
    private var highSurrogate: UInt32 = 0
    private var scalar: [UInt8] = []
    private var utf8Remaining = 0
    private var storage: [UInt8] = []
    private var keyTooLong = false
    private var embedded: EmbeddedProjection?
    private var reply: ReplyProjection?
    private(set) var failure: FeedError?

    init(key: Bool, rule: ProjectionRule, rejectOversizedKeys: Bool = false) {
        isKey = key
        self.rule = rule
        self.rejectOversizedKeys = rejectOversizedKeys
        if case let .embedded(inner) = rule { embedded = EmbeddedProjection(rule: inner) }
        else { embedded = nil }
        if case .reply = rule { reply = ReplyProjection() }
        else { reply = nil }
    }

    var key: String? { keyTooLong ? nil : String(decoding: storage, as: UTF8.self) }
    var retainedBytes: Int { storage.count + (embedded?.parser.liveRetainedBytes ?? 0) + (reply?.retainedBytes ?? 0) }

    func value() -> ProjectedJSON {
        do {
            if let embedded { return .string(try embedded.value()) }
            if let reply { return .string(try reply.value()) }
        } catch { deferFailure(error) }
        return .string(String(decoding: storage, as: UTF8.self))
    }

    func consume(_ byte: UInt8) throws -> Bool {
        switch escape {
        case .raw:
            if utf8Remaining > 0 {
                guard (128...191).contains(byte) else { throw ProjectionFailure.malformed }
                scalar.append(byte)
                utf8Remaining -= 1
                if utf8Remaining == 0 {
                    guard String(bytes: scalar, encoding: .utf8) != nil else { throw ProjectionFailure.malformed }
                    try emit(scalar)
                    scalar.removeAll(keepingCapacity: true)
                }
            } else if byte == 34 { return true }
            else if byte == 92 { escape = .escaped }
            else if byte < 32 { throw ProjectionFailure.malformed }
            else if byte < 128 { try emitByte(byte) }
            else {
                switch byte { case 194...223: utf8Remaining = 1; case 224...239: utf8Remaining = 2; case 240...244: utf8Remaining = 3; default: throw ProjectionFailure.malformed }
                scalar = [byte]
            }
        case .escaped:
            escape = .raw
            switch byte {
            case 34, 92, 47: try emit([byte])
            case 98: try emit([8])
            case 102: try emit([12])
            case 110: try emit([10])
            case 114: try emit([13])
            case 116: try emit([9])
            case 117: escape = .unicode(0, 0)
            default: throw ProjectionFailure.malformed
            }
        case let .unicode(count, code), let .lowUnicode(count, code):
            guard let digit = Self.hex(byte) else { throw ProjectionFailure.malformed }
            let value = code * 16 + digit
            let low: Bool
            if case .lowUnicode = escape { low = true } else { low = false }
            if count < 3 { escape = low ? .lowUnicode(count + 1, value) : .unicode(count + 1, value) }
            else if low {
                guard (0xDC00...0xDFFF).contains(value) else { throw ProjectionFailure.malformed }
                try emitScalar(0x10000 + (highSurrogate - 0xD800) * 1024 + value - 0xDC00)
                escape = .raw
            } else if (0xD800...0xDBFF).contains(value) { highSurrogate = value; escape = .lowSlash }
            else {
                guard !(0xDC00...0xDFFF).contains(value) else { throw ProjectionFailure.malformed }
                try emitScalar(value)
                escape = .raw
            }
        case .lowSlash:
            guard byte == 92 else { throw ProjectionFailure.malformed }
            escape = .lowU
        case .lowU:
            guard byte == 117 else { throw ProjectionFailure.malformed }
            escape = .lowUnicode(0, 0)
        }
        return false
    }

    private func emitScalar(_ value: UInt32) throws {
        guard let scalar = UnicodeScalar(value) else { throw ProjectionFailure.malformed }
        try emit(Array(String(scalar).utf8))
    }

    private func emitByte(_ byte: UInt8) throws {
        if isKey {
            guard !keyTooLong else { return }
            if storage.count < 512 { storage.append(byte) }
            else {
                if rejectOversizedKeys { throw FeedError.oversized }
                storage.removeAll(); keyTooLong = true
            }
        } else if embedded != nil || reply != nil { try emit([byte]) }
        else if case let .string(maximum) = rule {
            guard storage.count < maximum else { throw FeedError.oversized }
            storage.append(byte)
        }
    }

    private func emit(_ bytes: [UInt8]) throws {
        if isKey {
            if storage.count + bytes.count <= 512, !keyTooLong { storage.append(contentsOf: bytes) }
            else {
                if rejectOversizedKeys { throw FeedError.oversized }
                storage.removeAll(); keyTooLong = true
            }
        } else if let embedded {
            do { try embedded.consume(bytes) } catch { deferFailure(error) }
        } else if let reply {
            do { try reply.consume(bytes) } catch { deferFailure(error) }
        }
        else if case let .string(maximum) = rule {
            guard storage.count + bytes.count <= maximum else { throw FeedError.oversized }
            storage.append(contentsOf: bytes)
        }
    }

    private func deferFailure(_ error: any Error) {
        failure = error as? FeedError ?? .invalidRollout
        embedded = nil
        reply = nil
    }

    private static func hex(_ byte: UInt8) -> UInt32? {
        switch byte { case 48...57: UInt32(byte - 48); case 65...70: UInt32(byte - 55); case 97...102: UInt32(byte - 87); default: nil }
    }
}
