import Foundation
import Testing
@testable import DesktopFeed

@Suite struct RolloutBindingProjectionTests {
    private func project(_ source: String) throws -> [String: Any] {
        let data = try RolloutJSONLProjection.bindingDocument(Data(source.utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func rejects(_ source: Data) {
        #expect(throws: (any Error).self) { try RolloutJSONLProjection.bindingDocument(source) }
    }

    @Test func headerAndTaskWitnessKeepOnlyIdentityFields() throws {
        let header = try project("""
        {"type":"session_meta","payload":{"id":"synthetic-state-id","cwd":"PRIVATE-CWD", "instructions":"\(String(repeating: "private", count: 4000))", "other":{"nested":[1,true,null]}}}
        """)
        #expect(Set(header.keys) == ["type", "payload"])
        let headerPayload = try #require(header["payload"] as? [String: Any])
        #expect(Set(headerPayload.keys) == ["id"])
        #expect(headerPayload["id"] as? String == "synthetic-state-id")
        let task = try project("""
        {"timestamp":"ignored","type":"event_msg","payload":{"type":"task_started","turn_id":"synthetic-history-turn","id":"optional-id","private":{"text":"PRIVATE-CONTENT"}}}
        """)
        let payload = try #require(task["payload"] as? [String: Any])
        #expect(Set(payload.keys) == ["type", "turn_id", "id"])
        #expect(payload["turn_id"] as? String == "synthetic-history-turn")
        #expect(payload["type"] as? String == "task_started")
        #expect(!String(decoding: try RolloutJSONLProjection.bindingDocument(Data("{\"private\":\"SECRET\"}".utf8)), as: UTF8.self).contains("SECRET"))
    }

    @Test func everyObjectRejectsDuplicatesIncludingEscapedAndDiscardedKeys() {
        let documents = [
            #"{"type":"session_meta","type":"event_msg"}"#,
            #"{"payload":{"id":"one","id":"two"}}"#,
            #"{"payload":{"turn_id":"one","turn_\u0069d":"two"}}"#,
            #"{"unknown":1,"unknown":2}"#,
            #"{"ignored":{"same":1,"same":2}}"#,
            #"{"ignored":[{"nested":{"same":1,"same":2}}]}"#,
            #"{"payload":{"ignored":{"same":1,"s\u0061me":2}}}"#,
            #"{"ignored":{"":0,"":1}}"#
        ]
        for source in documents { rejects(Data(source.utf8)) }
    }

    @Test func theSameKeyInSeparateObjectsIsAllowed() throws {
        _ = try project(#"{"ignored":[{"same":1},{"same":2}],"payload":{"id":"retained"}}"#)
    }

    @Test func malformedWholeDocumentAndUnknownFieldsCannotBypassValidation() {
        let documents = [
            "", " ", "{", "{}{}", "{} true", #"{"type":"session_meta","payload":{"id":"x"}"#,
            #"{"type":"session_meta","ignored":[1,]}"#, #"{"ignored":01}"#,
            #"{"ignored":"\q"}"#, #"{"ignored":"\uD800"}"#, #"{"ignored":"\uDC00"}"#,
            #"{"ignored":"\uD800\u0041"}"#, #"{"ignored":true false}"#,
            "{\"ignored\":\"control\u{1}\"}"
        ]
        for source in documents { rejects(Data(source.utf8)) }
        for invalid in [[UInt8](arrayLiteral: 0xC0, 0xAF), [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xE2, 0x82]] {
            var source = Data("{\"ignored\":\"".utf8)
            source.append(contentsOf: invalid)
            source.append(Data("\"}".utf8))
            rejects(source)
        }
    }

    @Test func escapedIdentifiersAndValidUnknownUnicodeAreDecodedExactly() throws {
        let result = try project(#"{"type":"session_meta","payload":{"id":"s\u0079nthetic-\uD83D\uDE3A"},"ignored":"原始UTF8 🐈"}"#)
        let payload = try #require(result["payload"] as? [String: Any])
        #expect(payload["id"] as? String == "synthetic-😺")
    }

    @Test func bindingInputAndIdentifierBudgetsRejectInsteadOfTruncating() throws {
        let small = Data("{}".utf8)
        var boundary = small
        boundary.append(Data(repeating: 32, count: 65_536 - small.count))
        _ = try RolloutJSONLProjection.bindingDocument(boundary)
        boundary.append(32)
        rejects(boundary)
        for field in ["type", "id", "turn_id"] {
            let whereValue = field == "type" ? "{\"type\":\"%@\"}" : "{\"payload\":{\"\(field)\":\"%@\"}}"
            _ = try project(String(format: whereValue, String(repeating: "x", count: 512)))
            rejects(Data(String(format: whereValue, String(repeating: "x", count: 513)).utf8))
        }
    }

    @Test func everyKeyHasDecodedByteLimitAndObjectAndDocumentCountLimits() throws {
        _ = try project("{\"\(String(repeating: "k", count: 512))\":null}")
        rejects(Data("{\"\(String(repeating: "k", count: 513))\":null}".utf8))
        rejects(Data("{\"\(String(repeating: "猫", count: 171))\":null}".utf8))
        rejects(Data("{\"\(String(repeating: "\\u0061", count: 513))\":null}".utf8))
        func object(_ count: Int) -> String {
            "{" + (0..<count).map { "\"k\($0)\":null" }.joined(separator: ",") + "}"
        }
        _ = try project(object(1024))
        rejects(Data(object(1025).utf8))
        // Root key plus 2047 nested keys is the allowed document total. Each
        // nested object remains beneath the separate per-object limit.
        _ = try project("{\"ignored\":[\(object(1024)),\(object(1023))]}")
        rejects(Data("{\"ignored\":[\(object(1024)),\(object(1024))]}".utf8))
    }

    @Test func discardedDepthStillUsesTheExistingBound() throws {
        _ = try project("{\"ignored\":" + String(repeating: "[", count: 63) + "0" + String(repeating: "]", count: 63) + "}")
        rejects(Data(("{\"ignored\":" + String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64) + "}").utf8))
    }

    @Test func ordinaryEventProjectionKeepsItsPreviousLargeInputAndKeyPolicy() throws {
        let large = Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn\"},\"ignored\":\"\(String(repeating: "x", count: 1_100_000))\"}".utf8)
        rejects(large)
        _ = try RolloutJSONLProjection.document(large)
        let ignoredDuplicate = Data(#"{"ignored":{"same":1,"same":2},"payload":{"turn_id":"turn"}}"#.utf8)
        _ = try RolloutJSONLProjection.document(ignoredDuplicate)
        var stream = RolloutJSONLProjection()
        var lines = 0
        var jsonl = large
        jsonl.append(10)
        for start in stride(from: 0, to: jsonl.count, by: RolloutJSONLProjection.readBudget) {
            try stream.consume(jsonl.subdata(in: start..<min(start + RolloutJSONLProjection.readBudget, jsonl.count))) { _ in lines += 1 }
        }
        #expect(lines == 1)
        #expect(!stream.hasPartialRecord)
    }
}
