import AppKit
import Carbon
import IslandCore
import Testing
@testable import CodexIsland

@MainActor private final class NativeShortcutMock: ShortcutRegistering {
    private(set) var registrations = 0
    func register(action: @escaping @MainActor () -> Void) -> OSStatus {
        registrations += 1
        return noErr
    }
    func unregister() {}
}

// Requires a desktop graphics environment, just like the native gallery. This
// creates only hidden Island UI; it never activates an app or reads Codex data.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_ISLAND_TEST_RENDER_PREVIEWS"] == "1",
                         "Set CODEX_ISLAND_TEST_RENDER_PREVIEWS=1 on a Mac with working graphics"))
func nativeSettingsAndMenusSwitchAllFourLanguagesWithoutChangingSessionState() throws {
    let application = NSApplication.shared
    let originalMenu = application.mainMenu
    let originalLanguage = L10n.shared.language
    let originalKeyWindow = application.keyWindow
    let originalWindows = Set(application.windows.map(ObjectIdentifier.init))
    L10n.shared.configure(language: .en)
    defer {
        application.mainMenu = originalMenu
        L10n.shared.configure(language: originalLanguage)
    }

    let model = IslandModel()
    model.preferences.values.selectedPetID = "synthetic-native-pet"
    model.sessionTitle = "Synthetic 标题 🐈 日本語"
    model.connection = .connected
    model.isLocalFeed = true
    model.activity = .thinking
    model.summary = .reduce([.running, .running])
    let originalSummary = model.summary
    let originalSelectedPet = model.pets.selectedID
    let originalTitle = model.title
    let login = LoginItemController()
    let hotKeyService = NativeShortcutMock()
    let shortcut = ShortcutController(service: hotKeyService)
    let settings = SettingsWindowController(model: model, refreshPets: {}, openCodex: {},
        refreshStatus: {}, reviewOnboarding: {}, loginItem: login, shortcut: shortcut)
    defer { settings.close(); shortcut.close() }
    let window = try #require(application.windows.first {
        !originalWindows.contains(ObjectIdentifier($0)) && $0.title == "Codex Island Settings"
    })
    let menus = MenuBarController(model: model, openCodex: {}, showSettings: {}, refreshPets: {},
        refreshStatus: {}, toggleClickThrough: {}, remainingSeconds: { 0 })
    defer { menus.close() }
    #expect(!window.isVisible)

    let examples: [(AppLanguage, String, String, String, String)] = [
        (.en, "Codex Island Settings", "Edit", "Copy", "Settings…"),
        (.zhHans, "Codex Island 设置", "编辑", "复制", "设置…"),
        (.zhHant, "Codex Island 設定", "編輯", "複製", "設定…"),
        (.ja, "Codex Island 設定", "編集", "コピー", "設定…")
    ]
    for (language, windowTitle, editTitle, copyTitle, settingsTitle) in examples {
        model.preferences.values.language = language
        L10n.shared.configure(language: language)
        settings.refreshLanguage()
        menus.refreshLanguage()
        let actualMainMenu = try #require(application.mainMenu)
        let editItem = try #require(actualMainMenu.items.last)
        let editMenu = try #require(editItem.submenu)
        #expect(editItem.title == editTitle && editMenu.title == editTitle)
        #expect(editMenu.items.contains { $0.title == copyTitle && $0.action == NSSelectorFromString("copy:") })
        // AppKit asks the delegate to populate the application menu on opening.
        // Exercise that callback without opening a menu or taking focus.
        let applicationMenu = try #require(actualMainMenu.items.first?.submenu)
        #expect(applicationMenu.items.contains { $0.title == settingsTitle && $0.keyEquivalent == "," })
        menus.menuWillOpen(applicationMenu)
        #expect(applicationMenu.items.contains { $0.title == settingsTitle && $0.keyEquivalent == "," })
        let miniIndex = try #require(applicationMenu.items.firstIndex { $0.action == NSSelectorFromString("toggleMiniMode") })
        #expect(applicationMenu.items[miniIndex].title == L10n.value("settings.mode_mini"))
        #expect(applicationMenu.items[miniIndex].state == .off)
        applicationMenu.performActionForItem(at: miniIndex)
        #expect(model.preferences.values.displayMode == .mini)
        menus.menuWillOpen(applicationMenu)
        #expect(applicationMenu.items[miniIndex].state == .on)
        applicationMenu.performActionForItem(at: miniIndex)
        #expect(model.preferences.values.displayMode == .full)
        menus.menuDidClose(applicationMenu)

        #expect(application.windows.contains { $0 === window && $0.title == windowTitle })
        #expect(!window.isVisible)
        #expect(application.keyWindow === originalKeyWindow)
        #expect(model.title == originalTitle && model.sessionTitle == originalTitle)
        #expect(model.summary == originalSummary && model.state == .running)
        #expect(model.connection == .connected && model.activity == .thinking && model.isLocalFeed)
        #expect(model.preferences.values.selectedPetID == "synthetic-native-pet")
        #expect(model.pets.selectedID == originalSelectedPet)
        #expect(login.status == .unavailable && hotKeyService.registrations == 0)
    }
}
