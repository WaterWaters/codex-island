import AppKit
import SwiftUI
import IslandCore

private typealias SettingState<Value> = SwiftUI.State<Value>

@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    init(model: IslandModel, refreshPets: @escaping @MainActor () -> Void,
         openApplication: @escaping @MainActor (SourceProvider) -> Void,
         refreshStatus: @escaping @MainActor () -> Void, reviewOnboarding: @escaping @MainActor () -> Void,
         loginItem: LoginItemController, shortcut: ShortcutController) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = String(localized: SetupText.settingsTitle)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: IslandSettingsView(model: model, refreshPets: refreshPets,
            openApplication: openApplication, refreshStatus: refreshStatus, reviewOnboarding: reviewOnboarding,
            loginItem: loginItem, shortcut: shortcut))
        window.center()
    }
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func refreshLanguage() { window.title = String(localized: SetupText.settingsTitle) }
    func close() { window.close() }
}

private struct IslandSettingsView: View {
    let model: IslandModel
    let refreshPets: @MainActor () -> Void
    let openApplication: @MainActor (SourceProvider) -> Void
    let refreshStatus: @MainActor () -> Void
    let reviewOnboarding: @MainActor () -> Void
    let loginItem: LoginItemController
    let shortcut: ShortcutController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon = BrandAssets.colorIcon {
                    Image(nsImage: icon).resizable().scaledToFit()
                        .frame(width: 44, height: 44).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Codex Island").font(.title2.weight(.semibold))
                    Text(L10n.text("让工作状态留在视线里")).foregroundStyle(.secondary)
                }
                Spacer()
                if let frame = model.pets.atlas?.frame(motion: .idle, index: 0) {
                    Image(decorative: frame, scale: 2).resizable().scaledToFit().frame(width: 56, height: 60)
                }
            }.padding(22)
            TabView {
                GeneralSettingsView(model: model, reviewOnboarding: reviewOnboarding, loginItem: loginItem, shortcut: shortcut)
                    .tabItem { Label { Text(SetupText.general) } icon: { Image(systemName: "gearshape") } }
                AppearanceSettingsView(model: model, refreshPets: refreshPets)
                    .tabItem { Label { Text(SetupText.appearance) } icon: { Image(systemName: "paintpalette") } }
                ConnectionSettingsView(model: model, refreshStatus: refreshStatus, openApplication: openApplication)
                    .tabItem { Label { Text(SetupText.connection) } icon: { Image(systemName: "link") } }
                ExperimentalSettingsView(model: model)
                    .tabItem { Label { Text(SetupText.experiments) } icon: { Image(systemName: "flask") } }
            }.padding(.horizontal, 12)
            Divider()
            HStack {
                Button(L10n.text("恢复默认")) { model.preferences.reset() }
                Spacer()
                Button(L10n.text("打开 Codex")) { openApplication(.codex) }
                Button(L10n.text("退出")) { NSApp.terminate(nil) }
            }.padding(16)
        }
        .frame(width: 580, height: 680)
    }

}

private struct GeneralSettingsView: View {
    let model: IslandModel
    let reviewOnboarding: @MainActor () -> Void
    let loginItem: LoginItemController
    let shortcut: ShortcutController

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section {
                Toggle(L10n.text("显示岛"), isOn: $preferences.values.isVisible)
                Toggle(L10n.text("隐藏会话标题"), isOn: $preferences.values.hideSessionTitle)
                Text(L10n.text("启用后，岛、悬停和 VoiceOver 均不显示会话标题。"))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(L10n.text("语言"), selection: $preferences.values.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(verbatim: language == .system ? L10n.text("跟随系统") : language.displayName).tag(language)
                    }
                }
                Text(SetupText.resource("settings.general.menu_hint", "隐藏后仍可通过菜单栏水猫图标恢复岛、进入设置或退出。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(action: reviewOnboarding) { Text(SetupText.reviewGuide) }
            }
            Section(L10n.text("启动与快捷键")) {
                Toggle(L10n.text("登录时启动"), isOn: Binding(get: {
                    loginItem.status == .enabled || loginItem.status == .approvalRequired
                }, set: { loginItem.setEnabled($0) }))
                    .disabled(loginItem.status == .unavailable)
                Text(L10n.text(loginItem.status.message)).font(.caption).foregroundStyle(.secondary)
                if loginItem.failed {
                    Text(L10n.text("无法更改登录项，请检查系统设置中的实际状态。"))
                        .font(.caption).foregroundStyle(.red)
                }
                Button(L10n.text("打开登录项设置")) { loginItem.openSystemSettings() }
                Toggle(L10n.text("快捷显示或隐藏 · ⌃⌥⌘I"), isOn: $preferences.values.shortcutEnabled)
                switch shortcut.status {
                case .failed:
                    Text(L10n.text("快捷键注册失败或已被占用。请关闭后重试，菜单栏仍可显示或隐藏岛。"))
                        .font(.caption).foregroundStyle(.red)
                case .registered:
                    Text(L10n.text("快捷键已注册")).font(.caption).foregroundStyle(.secondary)
                case .disabled: EmptyView()
                }
            }
            Section(L10n.text("临时穿透")) {
                Text(L10n.text("中键单击岛后，岛会半透明，30 秒内点击可穿过岛。菜单栏也可以启动穿透或提前恢复交互。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).onAppear { loginItem.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
    }
}

private struct AppearanceSettingsView: View {
    @SettingState private var displays = DisplayCatalog.current
    let model: IslandModel
    let refreshPets: @MainActor () -> Void

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section(L10n.text("岛与显示")) {
                Picker(L10n.value("settings.display_mode"), selection: $preferences.values.displayMode) {
                    Text(L10n.value("settings.mode_full")).tag(IslandDisplayMode.full)
                    Text(L10n.value("settings.mode_mini")).tag(IslandDisplayMode.mini)
                }
                Text(L10n.value("settings.mini_hint"))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(L10n.text("显示器"), selection: $preferences.values.preferredDisplayID) {
                    Text(L10n.text("主显示器")).tag(String?.none)
                    ForEach(displays, id: \.id) { display in
                        Text(verbatim: display.name).tag(Optional(display.id))
                    }
                    if let selected = preferences.values.preferredDisplayID,
                       !displays.contains(where: { $0.id == selected }) {
                        Text(L10n.text("指定显示器暂不可用")).tag(Optional(selected))
                    }
                }
                Text(L10n.text("指定屏幕断开时回落主屏，重新接入后自动恢复。"))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(L10n.text("外观预设"), selection: Binding(get: {
                    preferences.values.appearancePreset
                }, set: { preferences.values.applyPreset($0) })) {
                    ForEach(AppearancePreset.allCases, id: \.self) { preset in
                        Text(L10n.text(presetTitle(preset))).tag(preset)
                    }
                }
                IslandView(model: model, geometry: IslandGeometry.layout(screenWidth: 1440,
                    notchWidth: 0, notchHeight: 0, expanded: true,
                    contentHeight: preferences.values.contentHeight,
                    displayMode: preferences.values.displayMode), openCodex: {})
                    .allowsHitTesting(false).accessibilityHidden(true)
                    .frame(maxWidth: .infinity)
                    .frame(height: preferences.values.displayMode == .mini ? 38 : preferences.values.contentHeight + 10)

                if preferences.values.displayMode == .full {
                    LabeledContent(L10n.text("岛高度"), value: "\(Int(preferences.values.contentHeight)) pt")
                    Slider(value: $preferences.values.contentHeight, in: 60...140, step: 2)
                        .accessibilityLabel(L10n.text("岛高度"))
                    Text(L10n.text("调整刘海下方的内容高度，修改即时生效。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L10n.text("宠物")) {
                if model.pets.pets.isEmpty {
                    Text(L10n.text("尚未找到可用宠物")).foregroundStyle(.secondary)
                } else {
                    Picker(L10n.text("岛上的宠物"), selection: $preferences.values.selectedPetID) {
                        ForEach(model.pets.pets) { pet in Text(verbatim: pet.name).tag(pet.id) }
                    }
                }
                HStack {
                    Text(model.pets.statusMessage).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if model.pets.isLoading { ProgressView().controlSize(.small) }
                    Button(L10n.text("重新同步"), action: refreshPets).disabled(model.pets.isLoading)
                }
                Text(L10n.text("支持 Codex 内置、本地自定义和已缓存的云端宠物。只切换岛的宠物，不修改 Codex。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("灯光与动态")) {
                IslandColorRow(title: L10n.text("霓虹主色"), hex: customColor(\.neonPrimary))
                IslandColorRow(title: L10n.text("霓虹辅色"), hex: customColor(\.neonSecondary))
                IslandColorRow(title: L10n.text("需要介入 · 脉冲"), hex: customColor(\.inputPulse))
                IslandColorRow(title: L10n.text("发生错误 · 脉冲"), hex: customColor(\.errorPulse))
                Toggle(L10n.text("播放动态效果"), isOn: Binding(get: {
                    preferences.values.animationsEnabled
                }, set: { preferences.values.setAnimationsEnabled($0) }))
            }
        }.formStyle(.grouped)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                displays = DisplayCatalog.current
            }
    }
    private func presetTitle(_ value: AppearancePreset) -> String {
        switch value { case .custom: "自定义"; case .standard: "默认"; case .quiet: "静谧"; case .highContrast: "高对比" }
    }
    private func customColor(_ path: WritableKeyPath<IslandSettings, String>) -> Binding<String> {
        Binding(get: { model.preferences.values[keyPath: path] }, set: {
            model.preferences.values[keyPath: path] = $0
            model.preferences.values.appearancePreset = .custom
        })
    }
}

private struct ExperimentalSettingsView: View {
    let model: IslandModel

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section(L10n.text("审批窗口识别 · 可选")) {
                Toggle(L10n.text("读取 Codex 的审批按钮"), isOn: Binding(get: {
                    preferences.values.approvalRecognitionEnabled == true
                }, set: { enabled in
                    preferences.values.approvalRecognitionEnabled = enabled
                    if enabled && !ApprovalAccess.isTrusted { ApprovalAccess.request() }
                }))
                Text(L10n.text("需要 macOS 辅助功能权限。该权限具备读取和控制界面的能力；本工具仅检查 Codex 的按钮标签，不执行点击，不保存聊天内容。"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L10n.text(model.approvalAccessMessage)).font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("打开辅助功能设置"), action: ApprovalAccess.openSettings)
                Text(L10n.text("仅识别已显示的审批卡片；未显示、最小化或其他语言的请求可能无法识别。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

private struct IslandColorRow: View {
    let title: String
    @Binding var hex: String
    @SettingState private var draft = ""

    var body: some View {
        HStack {
            ColorPicker(title, selection: Binding(get: { Color(islandHex: hex) }, set: { value in
            guard let rgb = NSColor(value).usingColorSpace(.sRGB) else { return }
                hex = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                             Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
            }), supportsOpacity: false)
            TextField("RRGGBB", text: $draft)
                .font(.system(.caption, design: .monospaced)).frame(width: 72)
                .accessibilityLabel(L10n.format("color.hex_accessibility", title))
                .help(L10n.text("输入 6 位十六进制颜色，例如 FF9F0A"))
        }
        .onAppear { draft = hex }
        .onChange(of: hex) { _, value in draft = value }
        .onChange(of: draft) { _, value in
            if let valid = IslandSettings.validatedHex(value), valid != hex { hex = valid }
        }
    }
}

extension Color {
    init(islandHex: String) {
        let number = UInt32(islandHex, radix: 16) ?? 0x66E6FF
        self.init(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
}
