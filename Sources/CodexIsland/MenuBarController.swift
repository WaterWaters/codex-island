import AppKit
import IslandCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: IslandModel
    private let openApplication: @MainActor (SourceProvider) -> Void
    private let showSettings: @MainActor () -> Void
    private let refreshPets: @MainActor () -> Void
    private let refreshStatus: @MainActor () -> Void
    private let toggleClickThrough: @MainActor () -> Void
    private let remainingSeconds: @MainActor () -> Int
    private var countdownItem: NSMenuItem?
    private var countdownTimer: Timer?

    init(model: IslandModel, openApplication: @escaping @MainActor (SourceProvider) -> Void,
         showSettings: @escaping @MainActor () -> Void, refreshPets: @escaping @MainActor () -> Void,
         refreshStatus: @escaping @MainActor () -> Void,
         toggleClickThrough: @escaping @MainActor () -> Void, remainingSeconds: @escaping @MainActor () -> Int) {
        self.model = model; self.openApplication = openApplication; self.showSettings = showSettings
        self.refreshPets = refreshPets; self.toggleClickThrough = toggleClickThrough; self.remainingSeconds = remainingSeconds
        self.refreshStatus = refreshStatus
        super.init()
        let image = BrandAssets.menuBarIcon
        item.button?.image = image
        item.button?.imageScaling = .scaleNone
        if image == nil { item.button?.title = "Island" }
        item.button?.setAccessibilityLabel(L10n.text("Codex Island 菜单"))
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        let main = NSMenu()
        let application = NSMenu(title: "Codex Island")
        application.delegate = self
        // Keep the same controls available while the settings window is active.
        menuWillOpen(application)
        menuDidClose(application)
        let entry = NSMenuItem(); entry.submenu = application; main.addItem(entry)
        installEditMenu(main)
        NSApp.mainMenu = main
        updateStatus()
    }

    private func installEditMenu(_ main: NSMenu) {
        let edit = NSMenu(title: L10n.text("编辑"))
        for (title, action, key) in [(L10n.text("撤销"), "undo:", "z"), (L10n.text("剪切"), "cut:", "x"), (L10n.text("复制"), "copy:", "c"), (L10n.text("粘贴"), "paste:", "v"), (L10n.text("全选"), "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: L10n.text("编辑"), action: nil, keyEquivalent: "")
        editItem.submenu = edit; main.addItem(editItem)
    }

    func refreshLanguage() {
        item.button?.setAccessibilityLabel(L10n.text("Codex Island 菜单"))
        if let main = NSApp.mainMenu {
            if let application = main.items.first?.submenu {
                menuWillOpen(application)
                menuDidClose(application)
            }
            if main.items.count > 1 { main.removeItem(at: 1) }
            installEditMenu(main)
        }
        updateStatus()
    }

    func updateStatus() {
        item.button?.toolTip = "Codex Island · \(model.displayDetail)" + (model.preferences.values.isVisible ? "" : " · " + L10n.text("岛已隐藏")) + (model.isClickThrough ? " · " + L10n.text("临时穿透中") : "")
    }

    @discardableResult private func add(_ title: String, to menu: NSMenu, action: Selector? = nil, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        menu.addItem(entry)
        return entry
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = add("Codex Island · \(model.displayDetail)", to: menu)
        header.isEnabled = false
        add(L10n.format("menu.open_provider", model.providerName), to: menu, action: #selector(openDisplayedApplication))
        let sources = NSMenu(title: L10n.value("menu.source"))
        for mode in StatusSourceMode.allCases {
            let entry = add(sourceTitle(mode), to: sources, action: #selector(selectSource(_:)))
            entry.representedObject = mode.rawValue
            entry.state = model.preferences.values.sourceMode == mode ? .on : .off
        }
        add(L10n.value("menu.source"), to: menu).submenu = sources
        menu.addItem(.separator())
        let visibility = add(L10n.text("显示岛"), to: menu, action: #selector(toggleVisibility))
        visibility.state = model.preferences.values.isVisible ? .on : .off
        let mini = add(L10n.value("settings.mode_mini"), to: menu, action: #selector(toggleMiniMode))
        mini.state = model.preferences.values.displayMode == .mini ? .on : .off
        let pets = NSMenu(title: L10n.text("宠物"))
        if model.pets.pets.isEmpty { add(L10n.text("暂无可用宠物"), to: pets).isEnabled = false }
        for pet in model.pets.pets {
            let entry = add(pet.name, to: pets, action: #selector(selectPet(_:)))
            entry.representedObject = pet.id
            entry.state = pet.id == model.pets.selectedID ? .on : .off
        }
        add(L10n.format("menu.pet", model.pets.displayName), to: menu).submenu = pets
        let motion = add(L10n.text("播放动态效果"), to: menu, action: #selector(toggleMotion))
        motion.state = model.preferences.values.animationsEnabled ? .on : .off
        countdownItem = add("", to: menu, action: #selector(changeClickThrough))
        updateCountdown()
        menu.addItem(.separator())
        add(String(localized: SetupText.settingsMenu), to: menu, action: #selector(settings), key: ",")
        add(L10n.text("重新同步状态"), to: menu, action: #selector(syncStatus))
        add(L10n.text("重新同步宠物与时长"), to: menu, action: #selector(syncPets)).isEnabled = !model.pets.isLoading
        menu.addItem(.separator())
        add(L10n.text("退出 Codex Island"), to: menu, action: #selector(quit), key: "q")
        countdownTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateCountdown() }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }
    func menuDidClose(_ menu: NSMenu) { countdownTimer?.invalidate(); countdownTimer = nil; countdownItem = nil }
    private func updateCountdown() {
        let remaining = remainingSeconds()
        countdownItem?.title = remaining > 0 ? L10n.count("menu.remaining", remaining) : L10n.text("半透明穿透 30 秒")
    }
    @objc private func toggleVisibility() { model.preferences.values.isVisible.toggle() }
    @objc private func toggleMiniMode() {
        model.preferences.values.displayMode = model.preferences.values.displayMode == .mini ? .full : .mini
    }
    @objc private func toggleMotion() {
        model.preferences.values.setAnimationsEnabled(!model.preferences.values.animationsEnabled)
    }
    @objc private func selectPet(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { model.preferences.values.selectedPetID = id }
    }
    @objc private func openDisplayedApplication() { openApplication(model.displayedProvider) }
    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = StatusSourceMode(rawValue: raw) else { return }
        model.preferences.values.sourceMode = mode
        model.resetRotationTiming()
        model.advanceRotation(now: Date())
    }
    private func sourceTitle(_ mode: StatusSourceMode) -> String {
        switch mode {
        case .codex: L10n.value("settings.source_codex")
        case .claude: L10n.value("settings.source_claude")
        case .rotate: L10n.value("settings.source_rotate")
        }
    }
    @objc private func settings() { showSettings() }
    @objc private func syncPets() { refreshPets() }
    @objc private func syncStatus() { refreshStatus() }
    @objc private func changeClickThrough() { toggleClickThrough() }
    @objc private func quit() { NSApp.terminate(nil) }
    func close() { countdownTimer?.invalidate(); NSStatusBar.system.removeStatusItem(item) }
}
