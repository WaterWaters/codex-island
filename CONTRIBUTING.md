# 参与开发

需要 macOS 14+、Swift 6+、Xcode 或 Command Line Tools，以及系统 SQLite。项目没有需要下载安装的第三方 Swift 包。

```bash
./Scripts/test.sh
./Scripts/package_app.sh
```

测试脚本使用当前 Swift 工具链默认构建系统；仅在工具链内存在对应库时显式加载 Testing 宏插件。脚本将 SwiftPM 缓存放在 `.build/`。`--disable-sandbox` 作用于构建过程，因此只对可信源码运行构建脚本。

默认测试使用临时 SQLite/事件夹具，不读取真实聊天、不申请辅助功能权限。要自行验证本机安装版素材，可显式运行：

```bash
CODEX_ISLAND_TEST_APP=/Applications/Codex.app ./Scripts/test.sh --filter installedCodexCatalogAndAllBuiltinAssetsAreReadable
```

使用实际安装路径。该检查不会操作真实审批或修改 Codex；与 GUI 联调和最低系统验收是不同检查。

四语言资源 key 与格式参数、偏好迁移及系统控制使用合成反例。原生图集、四语言布局和隐藏设置 / 菜单检查需在可用桌面显式启用：

```bash
CODEX_ISLAND_TEST_RENDER_PREVIEWS=1 ./Scripts/test.sh -c release
CODEX_ISLAND_TEST_SYSTEM_SHORTCUT=1 ./Scripts/test.sh -c release --filter realSystemShortcutDetectsConflictAndReleasesRegistration
```

第二个命令短暂注册 ⌃⌥⌘I、检查重复注册并注销，不发送按键；已有快捷键占用或沙盒禁止注册时应报失败，不改成成功。默认 CI 跳过这些桌面集成测试。四语言布局图只写忽略的 `local/`，不读取个人宠物，也不能替代实际操作或 VoiceOver 朗读。

修改来源或协议时增加有效的反例测试，保留只读、不把错误当空闲、不伪造未读的约定。修改 UI 时检查减少动态效果、隐藏恢复、穿透到期和显示器变化；不要用静态预览替代实际窗口验收。性能采样流程见 [性能说明](docs/performance.md)。

PR 请说明用户可见变化、验证结果及未覆盖环境。Bug 报告附系统 / 架构 / Swift / Codex 版本及脱敏错误类型；不要附聊天、数据库、完整 rollout 或证书。源码许可证为 MIT，图片授权另见 [素材说明](THIRD_PARTY_NOTICES.md)。
