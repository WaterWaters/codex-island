import Foundation

// Stable resource keys are resolved at the current display-language boundary.
@MainActor enum SetupText {
    static func resource(_ key: StaticString, _ value: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(stringLiteral: L10n.value(String(describing: key)))
    }

    static var settingsTitle: LocalizedStringResource { resource("settings.window.title", "Codex Island 设置") }
    static var settingsMenu: LocalizedStringResource { resource("settings.menu", "设置…") }
    static var general: LocalizedStringResource { resource("settings.tab.general", "常规") }
    static var appearance: LocalizedStringResource { resource("settings.tab.appearance", "外观") }
    static var connection: LocalizedStringResource { resource("settings.tab.connection", "连接") }
    static var experiments: LocalizedStringResource { resource("settings.tab.experiments", "实验功能") }
    static var reviewGuide: LocalizedStringResource { resource("onboarding.review", "重新查看使用引导…") }
    static var openCodex: LocalizedStringResource { resource("connection.open_codex", "打开 Codex") }
    static var resynchronize: LocalizedStringResource { resource("connection.resynchronize", "重新同步状态") }
    static var copyDiagnostics: LocalizedStringResource { resource("connection.copy_diagnostics", "复制脱敏诊断") }
    static var copied: LocalizedStringResource { resource("connection.diagnostics_copied", "已复制脱敏诊断") }
    static var copyFailed: LocalizedStringResource { resource("connection.diagnostics_copy_failed", "未能复制，请重试") }
    static var diagnosticPrivacy: LocalizedStringResource {
        resource("connection.diagnostics_privacy", "仅复制版本、固定原因和聚合同步健康值；不包含标题、会话 ID、用户路径或聊天内容。")
    }
    static var scope: LocalizedStringResource {
        resource("connection.source_scope", "来源：本机根会话的只读兼容适配。排除子代理；按状态优先级自动选择会话，不代表全部 Codex 聊天，也不支持完成未读同步。")
    }
    static var guideTitle: LocalizedStringResource { resource("onboarding.window.title", "开始使用 Codex Island") }
    static var guideWelcome: LocalizedStringResource { resource("onboarding.welcome.title", "把工作状态留在视线里") }
    static var guideMenu: LocalizedStringResource {
        resource("onboarding.welcome.menu", "菜单栏的水猫图标是入口：随时打开设置、显示或隐藏岛、重新同步。点击岛会打开 Codex，不会发送聊天或执行审批。")
    }
    static var guideStates: LocalizedStringResource {
        resource("onboarding.welcome.states", "工作中表示任务仍在进行；需要介入表示等待回答或可见审批；错误表示失败；空闲表示当前无活动，回合完成不等于未读。同步受限时，问答状态仍可能不完整。")
    }
    static var guideConnection: LocalizedStringResource { resource("onboarding.connection.title", "检查本机连接") }
    static var guidePrivacy: LocalizedStringResource { resource("onboarding.privacy.title", "先用基础功能，权限由你决定") }
    static var guidePrivacyBody: LocalizedStringResource {
        resource("onboarding.privacy.body", "基础状态不需要辅助功能权限。应用只在本机读取必要状态，不修改 Codex 数据。审批窗口识别默认关闭，可稍后在设置的实验功能中主动开启；它只检查已显示的按钮，不执行点击。")
    }
    static var guideReturn: LocalizedStringResource {
        resource("onboarding.return", "之后可从设置 → 常规重新查看本引导。偏好即时生效，宠物选择只影响岛。")
    }
    static var skip: LocalizedStringResource { resource("onboarding.skip", "跳过引导") }
    static var back: LocalizedStringResource { resource("onboarding.back", "上一步") }
    static var next: LocalizedStringResource { resource("onboarding.next", "下一步") }
    static var finish: LocalizedStringResource { resource("onboarding.finish", "开始使用") }
}
