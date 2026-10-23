import AppKit
import SwiftUI
import IslandCore

private typealias SettingState<Value> = SwiftUI.State<Value>

@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    init(model: IslandModel, refreshPets: @escaping @MainActor () -> Void, openCodex: @escaping @MainActor () -> Void) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Codex Island 设置"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: IslandSettingsView(model: model, refreshPets: refreshPets, openCodex: openCodex))
        window.center()
    }
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func close() { window.close() }
}

private struct IslandSettingsView: View {
    let model: IslandModel
    let refreshPets: @MainActor () -> Void
    let openCodex: @MainActor () -> Void

    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon = BrandAssets.colorIcon {
                    Image(nsImage: icon).resizable().scaledToFit()
                        .frame(width: 44, height: 44).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Codex Island").font(.title2.weight(.semibold))
                    Text("让工作状态留在视线里").foregroundStyle(.secondary)
                }
                Spacer()
                if let frame = model.pets.atlas?.frame(motion: .idle, index: 0) {
                    Image(decorative: frame, scale: 2).resizable().scaledToFit().frame(width: 56, height: 60)
                }
            }.padding(22)
            Form {
                Section("岛与显示") {
                    Toggle("显示岛", isOn: $preferences.values.isVisible)
                    LabeledContent("岛高度", value: "\(Int(preferences.values.contentHeight)) pt")
                    Slider(value: $preferences.values.contentHeight, in: 60...140, step: 2)
                        .accessibilityLabel("岛高度")
                    Text("调整刘海下方的内容高度，修改即时生效。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("宠物") {
                    if model.pets.pets.isEmpty {
                        Text("尚未找到可用宠物").foregroundStyle(.secondary)
                    } else {
                        Picker("岛上的宠物", selection: $preferences.values.selectedPetID) {
                            ForEach(model.pets.pets) { pet in Text(verbatim: pet.name).tag(pet.id) }
                        }
                    }
                    HStack {
                        Text(model.pets.statusMessage).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if model.pets.isLoading { ProgressView().controlSize(.small) }
                        Button("重新同步", action: refreshPets).disabled(model.pets.isLoading)
                    }
                    Text("支持 Codex 内置、本地自定义和已缓存的云端宠物。只切换岛的宠物，不修改 Codex。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("灯光与动态") {
                    IslandColorRow(title: "霓虹主色", hex: $preferences.values.neonPrimary)
                    IslandColorRow(title: "霓虹辅色", hex: $preferences.values.neonSecondary)
                    IslandColorRow(title: "需要介入 · 脉冲", hex: $preferences.values.inputPulse)
                    IslandColorRow(title: "发生错误 · 脉冲", hex: $preferences.values.errorPulse)
                    Toggle("播放动态效果", isOn: $preferences.values.animationsEnabled)
                }
                Section("临时穿透") {
                    Text("中键单击岛后，岛会半透明，30 秒内点击可穿过岛。菜单栏也可以启动穿透或提前恢复交互。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("审批窗口识别 · 可选") {
                    Toggle("读取 Codex 的审批按钮", isOn: Binding(get: {
                        preferences.values.approvalRecognitionEnabled == true
                    }, set: { enabled in
                        preferences.values.approvalRecognitionEnabled = enabled
                        if enabled && !ApprovalAccess.isTrusted { ApprovalAccess.request() }
                    }))
                    Text("需要 macOS 辅助功能权限。该权限具备读取和控制界面的能力；本工具仅检查 Codex 的按钮标签，不执行点击，不保存聊天内容。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(model.approvalAccessMessage).font(.caption).foregroundStyle(.secondary)
                    Button("打开辅助功能设置", action: ApprovalAccess.openSettings)
                    Text("仅识别已显示的审批卡片；未显示、最小化或其他语言的请求可能无法识别。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Button("恢复默认") { model.preferences.reset() }
                Spacer()
                Button("打开 Codex", action: openCodex)
                Button("退出") { NSApp.terminate(nil) }
            }.padding(16)
        }
        .frame(width: 510, height: 680)
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
                .accessibilityLabel("\(title)十六进制颜色")
                .help("输入 6 位十六进制颜色，例如 FF9F0A")
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
