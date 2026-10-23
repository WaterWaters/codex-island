@testable import DesktopFeed
import Foundation
import IslandCore
import Testing

private let largePadding = String(repeating: "s", count: 1_200_000)

private func largeEvent(_ payload: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": payload], options: .sortedKeys)
}

private func largeQuestion(_ id: String = "q") throws -> Data {
    try largeEvent(["type": "function_call", "name": "request_user_input", "call_id": id])
}

private func largeAsyncQuestion(_ id: String = "q", count: Int = 1, title: String = largePadding) throws -> Data {
    let arguments = String(decoding: try JSONSerialization.data(withJSONObject: [
        "questions": Array(repeating: ["title": title], count: count)
    ]), as: UTF8.self)
    return try largeEvent(["type": "function_call", "name": "request_user_input_async", "call_id": id, "arguments": arguments])
}

private func largeAcknowledgement(_ id: String = "q") throws -> Data {
    let output = String(decoding: try JSONSerialization.data(withJSONObject: ["accepted": true, "ignored": largePadding]), as: UTF8.self)
    return try largeEvent(["type": "function_call_output", "call_id": id, "output": output])
}

private func largeReply(_ id: String = "q") throws -> Data {
    let item = String(decoding: try JSONSerialization.data(withJSONObject: ["request_user_input_async", id, 0]), as: UTF8.self)
    let body = String(decoding: try JSONSerialization.data(withJSONObject: [["questionItemId": item, "answer": largePadding]]), as: UTF8.self)
    return try largeEvent(["type": "message", "role": "user", "content": [[
        "type": "input_text", "text": "\u{2003}<send_user_message_question_reply>" + body + "</send_user_message_question_reply>\u{2003}"
    ]]])
}

private func projectInChunks(_ data: Data, chunk: Int, signals: inout RolloutSignals) throws -> Int {
    var parser = RolloutJSONLProjection()
    var maximum = 0
    var start = 0
    while start < data.count {
        let end = min(start + chunk, data.count)
        try parser.consume(data.subdata(in: start..<end)) { line in try signals.consumeProjected(line, turnID: "t") }
        maximum = max(maximum, parser.retainedBytes)
        start = end
    }
    try parser.consume(Data([10])) { line in try signals.consumeProjected(line, turnID: "t") }
    #expect(!parser.hasPartialRecord)
    return maximum
}

@Test func largeOrdinaryOutputPreservesQuestionsBeforeAndAfterIt() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    try fixture.append(largeQuestion(), id: "a")
    try fixture.append(largeEvent(["type": "function_call_output", "call_id": "tool", "output": largePadding]), id: "a")
    try fixture.append(largeEvent(["type": "function_call_output", "call_id": "q"]), id: "a")
    try fixture.append(largeQuestion("after"), id: "a")
    let feed = LocalSessionFeed(home: fixture.root)
    for _ in 0..<4 {
        let partial = try await feed.read()
        #expect(!partial.caughtUp && partial.degradedThreads == 0)
        #expect(partial.snapshot.activities == [.running])
    }
    let complete = try await feed.read()
    #expect(complete.caughtUp && complete.degradedThreads == 0)
    #expect(complete.snapshot.activities == [.needsInput])
    try fixture.append(largeEvent(["type": "function_call_output", "call_id": "after"]), id: "a")
    #expect(try await feed.read().snapshot.activities == [.running])
}

@Test func largeAsyncQuestionAcceptanceAndAnswerOnlyRetainRequiredFields() throws {
    var signals = RolloutSignals()
    let questionBytes = try projectInChunks(largeAsyncQuestion(), chunk: 8191, signals: &signals)
    #expect(!signals.needsInput)
    let acceptanceBytes = try projectInChunks(largeAcknowledgement(), chunk: 8191, signals: &signals)
    #expect(signals.needsInput)
    let answerBytes = try projectInChunks(largeReply(), chunk: 8191, signals: &signals)
    #expect(!signals.needsInput)
    #expect(max(questionBytes, acceptanceBytes, answerBytes) < 4096)
}

@Test func largeRecordStillValidatesDiscardedUnicodeNumbersAndNestedStructure() throws {
    let ignored = #"{"n":-0.123e+123,"truth":true,"falsehood":false,"nothing":null,"tree":[{},[],{"x":"\uD83D\uDE3A\n\\\""}],"utf8":"猫😺"}"#
    var signals = RolloutSignals()
    let source = Data((#"{"padding":""# + largePadding + #"","ignored": "# + ignored + #", "payload":{"call_id":"q","name":"request_user_input","type":"function_call"},"type":"response_item"}"#).utf8)
    #expect(try projectInChunks(source, chunk: 7, signals: &signals) < 4096)
    #expect(signals.needsInput)
}

@Test func allByteBoundariesOfEscapesAndRawUTF8ProduceTheSameSignals() throws {
    let line = Data(#"{"discard":"猫😺\uD83D\uDE3A\"\\\n","payload":{"call_id":"q\u0031","name":"request_user_input","type":"function_call"},"type":"response_item"}"#.utf8)
    for chunk in 1...line.count {
        var signals = RolloutSignals()
        _ = try projectInChunks(line, chunk: chunk, signals: &signals)
        #expect(signals.needsInput)
        try signals.consume(largeEvent(["type": "function_call_output", "call_id": "q1"]), turnID: "t")
        #expect(!signals.needsInput)
    }
}

@Test func malformedDiscardedDataAndDuplicateCriticalKeysNeverCreateWaiting() async throws {
    let invalid = [
        #"{"ignored":01}"#, #"{"ignored":1.}"#, #"{"ignored":1e+}"#,
        #"{"ignored":[true,]}"#, #"{"ignored":{"x":true,}}"#,
        #"{"ignored":"\uD800"}"#, #"{"ignored":"\uDC00"}"#,
        #"{"ignored":"\x"}"#, #"{"ignored":tru}"#,
        #"{"type":"response_item","type":"ignored","payload":{"type":"function_call","name":"request_user_input","call_id":"q"}}"#,
        #"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","name":"request_user_input","call_id":"q"}}"#
    ]
    for text in invalid {
        #expect(throws: (any Error).self) { var signals = RolloutSignals(); try signals.consume(Data(text.utf8), turnID: "t") }
    }
    for bytes: [UInt8] in [[0xC0, 0x80], [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xE7, 34]] {
        var line = Data(#"{"ignored":""#.utf8)
        line.append(contentsOf: bytes)
        line.append(contentsOf: #""}"#.utf8)
        #expect(throws: (any Error).self) { var signals = RolloutSignals(); try signals.consume(line, turnID: "t") }
    }
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    try fixture.append(largeQuestion(), id: "a")
    try fixture.append(Data((#"{"ignored":""# + largePadding + #"","invalid":01}"#).utf8), id: "a")
    let feed = LocalSessionFeed(home: fixture.root)
    var result = try await feed.read()
    for _ in 0..<5 where result.degradedThreads == 0 { result = try await feed.read() }
    #expect(!result.caughtUp && result.degradedThreads == 1)
    #expect(result.snapshot.activities == [.running])
}

@Test func hugeUnknownKeyAndNestedFakePayloadCannotForgeQuestion() throws {
    var signals = RolloutSignals()
    let forged = #"{"type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"q"}}"#
    let line = Data((#"{""# + largePadding + #"":"ignored","unknown": ["# + forged + #"],"type":"unused"}"#).utf8)
    #expect(try projectInChunks(line, chunk: 262_144, signals: &signals) < 4096)
    #expect(!signals.needsInput)
}

@Test func parserBoundsNestingAndSemanticStorageInsteadOfLineLength() throws {
    let deep = Data((#"{"unknown":["# + String(repeating: "[", count: 64) + "0" + String(repeating: "]", count: 64) + "]}").utf8)
    #expect(throws: FeedError.oversized) { var signals = RolloutSignals(); try signals.consume(deep, turnID: "t") }
    let identifier = String(repeating: "x", count: 513)
    #expect(throws: FeedError.oversized) { var signals = RolloutSignals(); try signals.consume(largeQuestion(identifier), turnID: "t") }
    let excessive = try largeAsyncQuestion(count: 33, title: "ignored")
    #expect(throws: FeedError.oversized) { var signals = RolloutSignals(); try signals.consume(excessive, turnID: "t") }
}

@Test func publicSignalConsumptionCommitsOnlyAfterTheWholeInputIsValidated() throws {
    for suffix in [Data("\n{}\n".utf8), Data("\nbroken".utf8)] {
        var idle = RolloutSignals()
        var invalidQuestion = try largeQuestion()
        invalidQuestion.append(suffix)
        #expect(throws: (any Error).self) { try idle.consume(invalidQuestion, turnID: "t") }
        #expect(!idle.needsInput)
        var waiting = RolloutSignals()
        try waiting.consume(largeQuestion(), turnID: "t")
        var invalidAnswer = try largeEvent(["type": "function_call_output", "call_id": "q"])
        invalidAnswer.append(suffix)
        #expect(throws: (any Error).self) { try waiting.consume(invalidAnswer, turnID: "t") }
        #expect(waiting.needsInput)
    }
}

@Test func standaloneDocumentAcceptsJSONWhitespaceWhileFeedRemainsStrictJSONL() throws {
    let question = try largeQuestion()
    for whitespace in ["", " ", "\n", "\r\n\t "] {
        var signals = RolloutSignals()
        var document = Data(whitespace.utf8)
        document.append(question)
        document.append(contentsOf: whitespace.utf8)
        try signals.consume(document, turnID: "t")
        #expect(signals.needsInput)
    }
    let object = try JSONSerialization.jsonObject(with: question)
    var signals = RolloutSignals()
    try signals.consume(JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]), turnID: "t")
    #expect(signals.needsInput)
    var multiple = question
    multiple.append(contentsOf: "\n{}\n".utf8)
    #expect(throws: (any Error).self) { try signals.consume(multiple, turnID: "t") }
    #expect(signals.needsInput)
    var jsonl = RolloutJSONLProjection()
    #expect(throws: (any Error).self) { try jsonl.consume(Data("\n".utf8)) { _ in Issue.record("An empty JSONL record must remain invalid") } }
}

@Test func irrelevantEmbeddedFieldsPreserveExistingToolAndReplySemantics() throws {
    var signals = RolloutSignals()
    let unrelatedArguments = String(decoding: try JSONSerialization.data(withJSONObject: [
        "questions": Array(repeating: ["title": "ignored"], count: 33)
    ]), as: UTF8.self)
    try signals.consume(largeEvent(["arguments": unrelatedArguments, "type": "function_call", "call_id": "q", "name": "request_user_input"]), turnID: "t")
    #expect(signals.needsInput)
    try signals.consume(largeEvent(["type": "function_call_output", "call_id": "q", "output": []]), turnID: "t")
    #expect(!signals.needsInput)
    // Input cannot forge the deferred-error metadata generated by the projector.
    try signals.consume(largeEvent(["type": "function_call", "call_id": "q", "name": "request_user_input", "_island_projection_arguments_failure": "oversized"]), turnID: "t")
    #expect(signals.needsInput)
    // Duplicate accepted is ambiguous only for the actual async acknowledgement.
    try signals.consume(largeEvent(["type": "function_call_output", "call_id": "q", "output": #"{"accepted":false,"accepted":true}"#]), turnID: "t")
    #expect(!signals.needsInput)
    try signals.consume(largeAsyncQuestion(title: "small"), turnID: "t")
    #expect(throws: (any Error).self) {
        try signals.consume(largeEvent(["type": "function_call_output", "call_id": "q", "output": #"{"accepted":false,"accepted":true}"#]), turnID: "t")
    }
    #expect(!signals.needsInput)
}

@Test func existingThirtyTwoQuestionBoundaryAndEscapedCallIdentifiersRemainSupported() throws {
    var signals = RolloutSignals()
    let call = String(repeating: "\\\"", count: 256) // Exactly 512 decoded UTF-8 bytes.
    try signals.consume(largeAsyncQuestion(call, count: 32, title: "ignored"), turnID: "t")
    try signals.consume(largeAcknowledgement(call), turnID: "t")
    #expect(signals.needsInput)
    for index in 0..<32 {
        let id = String(decoding: try JSONSerialization.data(withJSONObject: ["request_user_input_async", call, index]), as: UTF8.self)
        let body = String(decoding: try JSONSerialization.data(withJSONObject: [["questionItemId": id]]), as: UTF8.self)
        let text = "<send_user_message_question_reply>" + body + "</send_user_message_question_reply>"
        try signals.consume(largeEvent(["type": "message", "role": "user", "content": [["type": "input_text", "text": text]]]), turnID: "t")
        #expect(signals.needsInput == (index < 31))
    }
}

@Test func aggregateReplyProjectionBudgetIsEnforcedWhileOrdinaryTextIsDiscarded() throws {
    let body = String(decoding: try JSONSerialization.data(withJSONObject: Array(repeating: ["questionItemId": String(repeating: "x", count: 3000)], count: 500)), as: UTF8.self)
    let text = "<send_user_message_question_reply>" + body + "</send_user_message_question_reply>"
    let source = try largeEvent(["type": "message", "role": "user", "content": [["type": "input_text", "text": text]]])
    var parser = RolloutJSONLProjection()
    var maximum = 0
    for start in stride(from: 0, to: source.count, by: RolloutJSONLProjection.readBudget) {
        try parser.consume(source.subdata(in: start..<min(start + RolloutJSONLProjection.readBudget, source.count))) { _ in Issue.record("Record must not complete before its newline") }
        maximum = max(maximum, parser.retainedBytes)
    }
    #expect(maximum > 500_000 && maximum <= 1_048_576)
    var signals = RolloutSignals()
    #expect(throws: FeedError.oversized) {
        try parser.consume(Data([10])) { line in try signals.consumeProjected(line, turnID: "t") }
    }
    #expect(!signals.needsInput)
}

@Test func fixedSeedGeneratedJSONAndChunkingAgreeWithFoundationValidation() throws {
    var seed: UInt64 = 0xC0DE_073
    func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed }
    func value(_ depth: Int) -> Any {
        switch next() % (depth > 0 ? 8 : 6) {
        case 0: return NSNull()
        case 1: return next() % 2 == 0
        case 2: return Int(next() % 1_000_000) - 500_000
        case 3: return Double(next() % 100_000) / -7.0
        case 4: return "猫😺\n\r\t\\\"/\u{0}\u{1}" + String(next())
        case 5: return String(repeating: "x", count: Int(next() % 70))
        case 6: return (0..<Int(next() % 5)).map { _ in value(depth - 1) }
        default: return ["payload": value(depth - 1), "nested": value(depth - 1)]
        }
    }
    for index in 0..<200 {
        let ignored = String(decoding: try JSONSerialization.data(withJSONObject: value(3), options: [.fragmentsAllowed, .sortedKeys]), as: UTF8.self)
        let payload = #""type":"response_item","payload":{"name":"request_user_input","call_id":"q","type":"function_call"}"#
        let line = Data((index.isMultiple(of: 2) ? "{\(payload),\"ignored\":\(ignored)}" : "{\"ignored\":\(ignored),\(payload)}").utf8)
        _ = try JSONSerialization.jsonObject(with: line)
        var signals = RolloutSignals()
        _ = try projectInChunks(line, chunk: Int(next() % 97) + 1, signals: &signals)
        #expect(signals.needsInput)
    }
}

@Test func halfLargeLineRemainsUnsynchronizedUntilNewlineThenTerminalClearsWait() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "a", status: "inProgress")
    try fixture.append(largeQuestion(), id: "a")
    let line = try largeEvent(["type": "function_call_output", "call_id": "tool", "output": largePadding])
    try fixture.append(line, id: "a", newline: false)
    let feed = LocalSessionFeed(home: fixture.root)
    for _ in 0..<6 {
        let result = try await feed.read()
        #expect(!result.caughtUp && result.degradedThreads == 0)
        #expect(result.snapshot.activities == [.running])
    }
    try fixture.append(Data(), id: "a")
    #expect(try await feed.read().snapshot.activities == [.needsInput])
    try fixture.append(Data(#"{"type":"event_msg","payload":{"type":"turn_complete","turn_id":"t"}}"#.utf8), id: "a")
    #expect(try await feed.read().snapshot.activities == [.running])
}

@Test func replacingOrTruncatingPartialLargeLineResetsParserAndSignals() async throws {
    for atomic in [false, true] {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.add(id: "a", status: "inProgress")
        try fixture.append(largeQuestion("old"), id: "a")
        try fixture.append(largeEvent(["type": "function_call_output", "call_id": "tool", "output": largePadding]), id: "a")
        let feed = LocalSessionFeed(home: fixture.root)
        #expect(!(try await feed.read()).caughtUp)
        try Data().write(to: fixture.rollout("a"), options: atomic ? .atomic : [])
        try fixture.append(largeQuestion("new"), id: "a")
        let replaced = try await feed.read()
        #expect(replaced.caughtUp && replaced.degradedThreads == 0)
        try fixture.append(largeEvent(["type": "function_call_output", "call_id": "new"]), id: "a")
        #expect(try await feed.read().snapshot.activities == [.running])
    }
}

@Test func largePartialSourceDoesNotDelayAHealthyQuestionOrCarryAcrossTurns() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.add(id: "large", status: "inProgress")
    try fixture.add(id: "healthy", status: "inProgress")
    try fixture.append(largeEvent(["type": "function_call_output", "call_id": "tool", "output": largePadding]), id: "large")
    try fixture.append(largeQuestion(), id: "healthy")
    let feed = LocalSessionFeed(home: fixture.root)
    let partial = try await feed.read()
    #expect(!partial.caughtUp && partial.degradedThreads == 0)
    #expect(partial.snapshot.activities.contains(.needsInput))
    let size = try Data(contentsOf: fixture.rollout("large")).count
    try fixture.execute("history", "UPDATE thread_turns SET turn_id='new',rollout_byte_offset=\(size) WHERE thread_id='large'")
    let changed = try await feed.read()
    #expect(changed.caughtUp && changed.degradedThreads == 0)
}
