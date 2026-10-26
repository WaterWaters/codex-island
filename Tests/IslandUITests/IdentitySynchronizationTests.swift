import CoreFoundation
import DesktopFeed
import Foundation
import IslandCore
import Testing
@testable import CodexIsland

@MainActor @Test func unresolvedIdentityDoesNotPresentAnIdleSummaryAsConfirmedIdle() {
    let previous = L10n.shared.language
    defer { L10n.shared.configure(language: previous) }
    let model = IslandModel()
    model.isLocalFeed = true
    model.connection = .connected
    model.summary = .reduce([])
    model.localFeedHealth = FeedHealth(caughtUp: true, unresolvedIdentity: true)
    for language in [AppLanguage.en, .zhHans, .zhHant, .ja] {
        L10n.shared.configure(language: language)
        #expect(model.detail == L10n.text("状态暂不可用"))
        #expect(model.detail != L10n.text(SessionActivity.idle.title))
        #expect(model.displayDetail.contains(L10n.text("同步受限")))
        #expect(model.accessibilityDescription.contains(L10n.text("状态暂不可用")))
        #expect(!model.accessibilityDescription.contains(L10n.text(SessionActivity.idle.title)))
        #expect(model.connectionPresentation.status == .identityLimited)
    }
}

@MainActor @Test func unresolvedIdentityPreservesConfirmedActivityAndShowsItsLimitedCoverage() {
    let previous = L10n.shared.language
    defer { L10n.shared.configure(language: previous) }
    L10n.shared.configure(language: .en)
    let model = IslandModel()
    model.isLocalFeed = true
    model.connection = .connected
    model.localFeedHealth = FeedHealth(caughtUp: false, degradedThreads: 1, unresolvedIdentity: true)
    let cases: [(WorkState, SessionActivity?, String)] = [
        (.running, .thinking, "思考中"), (.needsInput, .thinking, SessionActivity.needsInput.title),
        (.blocked, .thinking, SessionActivity.failed.title), (.ready, nil, WorkState.ready.title)
    ]
    for (state, activity, source) in cases {
        model.summary = .reduce([state])
        model.activity = activity
        #expect(model.state == state)
        #expect(model.detail == L10n.text(source))
        #expect(model.displayDetail.contains(L10n.text(source)))
        #expect(model.displayDetail.components(separatedBy: L10n.text("同步受限")).count == 2)
        #expect(model.connectionPresentation.status == .identityLimited)
    }
    // A visible approval stays authoritative without inventing a session link.
    model.summary = .reduce([])
    model.approvalUIIsPending = true
    #expect(model.state == .needsInput)
    #expect(model.detail == L10n.text("等待批准"))
    #expect(model.displayDetail.contains(L10n.text("同步受限")))
}

@MainActor @Test func resolvedIdentityAndAbsentHealthPreserveExistingIdleAndRecoveryBehavior() {
    let previous = L10n.shared.language
    defer { L10n.shared.configure(language: previous) }
    L10n.shared.configure(language: .en)
    let model = IslandModel()
    model.isLocalFeed = true
    model.connection = .connected
    model.summary = .reduce([])
    #expect(model.detail == L10n.text(SessionActivity.idle.title))
    model.localFeedHealth = FeedHealth(caughtUp: true, unresolvedIdentity: true)
    #expect(model.detail == L10n.text("状态暂不可用"))
    model.localFeedHealth = FeedHealth(caughtUp: true, unresolvedIdentity: false)
    #expect(model.detail == L10n.text(SessionActivity.idle.title))
    #expect(!model.displayDetail.contains(L10n.text("同步受限")))
    #expect(model.connectionPresentation.status == .connected)
    model.localFeedHealth = FeedHealth(caughtUp: false)
    #expect(model.connectionPresentation.status == .synchronizing)
    model.localFeedHealth = FeedHealth(caughtUp: false, degradedThreads: 1)
    #expect(model.connectionPresentation.status == .eventsLimited)
    #expect(model.detail == L10n.text(SessionActivity.idle.title))
}

@MainActor @Test func identityLimitedPresentationUsesFourLanguagesAndRetainsOtherConnectionScopes() throws {
    let previous = L10n.shared.language
    defer { L10n.shared.configure(language: previous) }
    let health = FeedHealth(caughtUp: false, degradedThreads: 2, retryingThreads: 1, unresolvedIdentity: true)
    let presentation = ConnectionPresentation(connection: .connected, health: health)
    #expect(presentation.status == .identityLimited)
    #expect(presentation.offersOpenCodex)
    #expect(presentation.symbol == "exclamationmark.triangle")
    let translations: [(AppLanguage, String, String)] = [
        (.en, "Connected · Some Status Unconfirmed", "Unconfirmed status does not mean idle."),
        (.zhHans, "已连接 · 部分状态待确认", "未确认的状态不代表空闲。"),
        (.zhHant, "已連線 · 部分狀態待確認", "未確認的狀態不代表閒置。"),
        (.ja, "接続済み · 一部の状態は未確認", "未確認は待機中を意味しません。")
    ]
    for (language, title, clarification) in translations {
        let bundle = try #require(L10n.localizedBundle(language.rawValue))
        let url = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let catalog = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
        #expect(catalog["connection.identity_limited.title"] == title)
        #expect(catalog["connection.identity_limited.next"]?.contains(clarification) == true)
        L10n.shared.configure(language: language)
        #expect(String(localized: presentation.title) == title)
        #expect(String(localized: presentation.nextStep).contains(clarification))
    }
    #expect(LocalizationSources.keys["已连接 · 部分状态待确认"] == "connection.identity_limited.title")
    #expect(ConnectionPresentation(connection: .unavailable, health: health).status == .temporaryFailure)
    #expect(ConnectionPresentation(connection: .connected, health: health, isDemo: true).status == .demo)
    #expect(ConnectionPresentation(connection: .connected, health: health, isExternal: true).status == .external)
}

@MainActor @Test func identityDiagnosticsExportOnlyTheClosedBooleanHealthField() throws {
    let model = IslandModel()
    model.isLocalFeed = true
    model.connection = .connected
    model.sessionTitle = "PRIVATE-TITLE /Users/private/session-identity"
    model.localFeedHealth = FeedHealth(caughtUp: false, unresolvedIdentity: true)
    let json = try #require(model.privacyDiagnostics.json())
    let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(Set(object.keys) == ["schemaVersion", "islandVersion", "codexVersion", "source", "connection",
                               "caughtUp", "degradedThreads", "retryingThreads", "unresolvedIdentity"])
    let flag = try #require(object["unresolvedIdentity"] as? NSNumber)
    #expect(CFGetTypeID(flag) == CFBooleanGetTypeID())
    #expect(flag.boolValue)
    #expect(object["connection"] as? String == "identityLimited")
    #expect(!json.contains("PRIVATE"))
    #expect(!json.contains("/Users/"))
    #expect(!json.contains("session-identity"))
    model.localFeedHealth = FeedHealth(caughtUp: true)
    #expect(model.privacyDiagnostics.unresolvedIdentity == false)
    model.localFeedHealth = nil
    #expect(model.privacyDiagnostics.unresolvedIdentity == nil)
    let absent = try #require(model.privacyDiagnostics.json())
    let absentObject = try #require(JSONSerialization.jsonObject(with: Data(absent.utf8)) as? [String: Any])
    #expect(absentObject["unresolvedIdentity"] == nil)
}
