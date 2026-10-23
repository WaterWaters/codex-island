import AppKit
import IslandCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: IslandModel
    private let openCodex: @MainActor () -> Void
    private let showSettings: @MainActor () -> Void
    private let refreshPets: @MainActor () -> Void
    private let refreshStatus: @MainActor () -> Void
    private let toggleClickThrough: @MainActor () -> Void
    private let remainingSeconds: @MainActor () -> Int
    private var countdownItem: NSMenuItem?
    private var countdownTimer: Timer?

    init(model: IslandModel, openCodex: @escaping @MainActor () -> Void,
         showSettings: @escaping @MainActor () -> Void, refreshPets: @escaping @MainActor () -> Void,
         refreshStatus: @escaping @MainActor () -> Void,
         toggleClickThrough: @escaping @MainActor () -> Void, remainingSeconds: @escaping @MainActor () -> Int) {
        self.model = model; self.openCodex = openCodex; self.showSettings = showSettings
        self.refreshPets = refreshPets; self.toggleClickThrough = toggleClickThrough; self.remainingSeconds = remainingSeconds
        self.refreshStatus = refreshStatus
        super.init()
        let image = BrandAssets.menuBarIcon
        item.button?.image = image
        item.button?.imageScaling = .scaleNone
        if image == nil { item.button?.title = "Island" }
        item.button?.setAccessibilityLabel("Codex Island 菜单")
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        let main = NSMenu()
        let application = NSMenu(title: "Codex Island")
        application.delegate = self
        // Keep the same controls available while the settings window is active.
        menuWillOpen(application)
        menuDidClose(application)
        let entry = NSMenuItem(); entry.submenu = application; main.addItem(entry)
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
        updateStatus()
    }

    func updateStatus() {
        item.button?.toolTip = "Codex Island · \(model.displayDetail)" + (model.preferences.values.isVisible ? "" : " · 岛已隐藏") + (model.isClickThrough ? " · 临时穿透中" : "")
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
        add("打开 Codex", to: menu, action: #selector(openApplication))
        menu.addItem(.separator())
        let visibility = add("显示岛", to: menu, action: #selector(toggleVisibility))
        visibility.state = model.preferences.values.isVisible ? .on : .off
        let pets = NSMenu(title: "宠物")
        if model.pets.pets.isEmpty { add("暂无可用宠物", to: pets).isEnabled = false }
        for pet in model.pets.pets {
            let entry = add(pet.name, to: pets, action: #selector(selectPet(_:)))
            entry.representedObject = pet.id
            entry.state = pet.id == model.pets.selectedID ? .on : .off
        }
        add("宠物 · \(model.pets.displayName)", to: menu).submenu = pets
        let motion = add("播放动态效果", to: menu, action: #selector(toggleMotion))
        motion.state = model.preferences.values.animationsEnabled ? .on : .off
        countdownItem = add("", to: menu, action: #selector(changeClickThrough))
        updateCountdown()
        menu.addItem(.separator())
        add("外观与设置…", to: menu, action: #selector(settings), key: ",")
        add("重新同步状态", to: menu, action: #selector(syncStatus))
        add("重新同步宠物与时长", to: menu, action: #selector(syncPets)).isEnabled = !model.pets.isLoading
        menu.addItem(.separator())
        add("退出 Codex Island", to: menu, action: #selector(quit), key: "q")
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
        countdownItem?.title = remaining > 0 ? "恢复岛交互（还剩 \(remaining) 秒）" : "半透明穿透 30 秒"
    }
    @objc private func toggleVisibility() { model.preferences.values.isVisible.toggle() }
    @objc private func toggleMotion() { model.preferences.values.animationsEnabled.toggle() }
    @objc private func selectPet(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { model.preferences.values.selectedPetID = id }
    }
    @objc private func openApplication() { openCodex() }
    @objc private func settings() { showSettings() }
    @objc private func syncPets() { refreshPets() }
    @objc private func syncStatus() { refreshStatus() }
    @objc private func changeClickThrough() { toggleClickThrough() }
    @objc private func quit() { NSApp.terminate(nil) }
    func close() { countdownTimer?.invalidate(); NSStatusBar.system.removeStatusItem(item) }
}
