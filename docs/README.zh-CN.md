<p align="center">
  <img src="assets/banner.png" alt="Codex Island — aquatic cat and terminal prompt" width="960">
</p>

<h1 align="center">Codex Island</h1>

<p align="center">Codex 进展，抬眼可见。<br>原生 macOS 状态岛，让当前活动、待回答的问题和小小陪伴留在屏幕一角。</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-0B7285?style=flat-square" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6%2B-F05138?style=flat-square" alt="Swift 6+">
  <img src="https://img.shields.io/badge/status-preview-64748B?style=flat-square" alt="Preview">
  <a href="https://github.com/WaterWaters/codex-island/actions/workflows/ci.yml"><img src="https://github.com/WaterWaters/codex-island/actions/workflows/ci.yml/badge.svg?branch=main" alt="macOS CI"></a>
  <a href="../LICENSE"><img src="https://img.shields.io/badge/license-MIT-22C55E?style=flat-square" alt="MIT license"></a>
</p>

<p align="center">
  <a href="../README.md">English</a> · <strong>简体中文</strong> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <a href="#previews">界面预览</a> · <a href="#features">功能亮点</a> · <a href="#getting-started">快速开始</a> · <a href="#privacy">隐私</a> · <a href="#documentation">文档</a>
</p>

Codex Island 将当前本机会话的标题和活动放在屏幕顶部。工作进行到哪一步、什么时候需要你回答，抬眼就能看到；点击状态岛即可回到 Codex。

**独立项目，与 OpenAI 无关联。** 当前为围绕本机 Codex 兼容性开发的 0.x 预览版。

<a id="previews"></a>
## 看看状态岛的样子

四种日常状态，分别展示在 MacBook 刘海屏和普通外接屏上。会话标题在上、当前活动在下，不同状态使用清晰可辨的轮廓提示。

下图使用合成内容和原生 SwiftUI 视图渲染，展示当前简体中文界面与缺少素材时的备用猫图形；屏幕背景为示意构图，并非桌面截图或硬件验收证据。[预览生成方式](assets/previews/README.md)。

| MacBook · 刘海屏 | 外接显示器 · 普通屏 |
| :---: | :---: |
| <img src="assets/previews/running-notched.png" alt="刘海屏上的工作中状态岛" width="440"><br><strong>工作中</strong><br>抬眼查看命令和工具活动。 | <img src="assets/previews/running-standard.png" alt="普通外接屏上的工作中状态岛" width="440"><br><strong>工作中</strong><br>抬眼查看命令和工具活动。 |
| <img src="assets/previews/needsInput-notched.png" alt="刘海屏上的待回答提示" width="440"><br><strong>需要你</strong><br>需要回答时，给你清晰的提示。 | <img src="assets/previews/needsInput-standard.png" alt="普通外接屏上的待回答提示" width="440"><br><strong>需要你</strong><br>需要回答时，给你清晰的提示。 |
| <img src="assets/previews/blocked-notched.png" alt="刘海屏上的工作受阻状态" width="440"><br><strong>工作受阻</strong><br>回合失败时，使用独立的错误状态。 | <img src="assets/previews/blocked-standard.png" alt="普通外接屏上的工作受阻状态" width="440"><br><strong>工作受阻</strong><br>回合失败时，使用独立的错误状态。 |
| <img src="assets/previews/idle-notched.png" alt="刘海屏上的空闲状态岛" width="440"><br><strong>空闲</strong><br>Codex 开着时，安静留在视线里。 | <img src="assets/previews/idle-standard.png" alt="普通外接屏上的空闲状态岛" width="440"><br><strong>空闲</strong><br>Codex 开着时，安静留在视线里。 |

<a id="features"></a>
## 少切几次窗口

- **标题与活动，一起呈现。** 两行信息展示思考、命令、文件修改和工具活动。
- **需要你时，给个提示。** 已识别的待回答问题触发脉冲，错误使用独立视觉状态。
- **融入 macOS。** SwiftUI 与 AppKit 原生界面，避让刘海，支持菜单栏控制和减少动态效果。
- **按你的习惯调整。** 自定义颜色、高度、显隐和动画；中键点击即可临时穿透 30 秒。
- **你的 Codex 小伙伴。** 支持内置、本地自定义和本机已缓存的云端宠物，不随包携带个人图片。云端素材缺失时，在 Codex 查看该宠物后重新同步。[素材来源与限制](pet-animation.md)。
- **默认只在本机工作。** 只读本地状态，应用没有遥测或网络服务。

<a id="getting-started"></a>
## 快速开始

**预览版安装包：** [GitHub Releases](https://github.com/WaterWaters/codex-island/releases)。发布流程检查通过后，会提供 universal DMG 和 ZIP。[发布指南](releases.md)。

**从源码构建：** 需要 macOS 14+、Swift 6+，以及 Xcode 或 Command Line Tools。实时本机状态需要安装 Codex。项目没有第三方 Swift 包依赖。

在项目根目录执行：

```bash
./Scripts/package_app.sh
open build/CodexIsland.app
```

启动后可在菜单栏找到应用。Codex 运行期间，状态岛在空闲时仍会保留；Codex 退出后隐藏。也可以从菜单栏手动显示或隐藏。

v0.7.3 之后的源码新增可跳过的首次引导，以及常规 / 外观 / 连接 / 实验功能四组设置。连接页提供下一步和脱敏诊断复制；这些新增能力尚未包含在 v0.7.3 下载包中。[首次使用与连接检查](getting-started.md)。

未发布源码另提供标题隐私、可选登录时启动、主动启用的 ⌃⌥⌘I 显隐快捷键、固定显示器与重接恢复，以及默认 / 静谧 / 高对比预设。设置即时生效，登录批准与快捷键冲突显示实际结果。

> [!NOTE]
> 当前应用包只做了本机 ad-hoc 签名，未公证，默认构建当前 CPU 架构。已验证 Apple Silicon / Swift 6.4；macOS 14 和 Intel 的实机运行仍待验收。

<a id="usage"></a>
## 日常使用

| 操作 | 效果 |
| --- | --- |
| 左键点击状态岛 | 打开 Codex |
| 中键点击状态岛 | 半透明，并让鼠标穿透 30 秒 |
| 打开菜单栏菜单 | 显示或隐藏、换宠物、调整外观，分别重新同步状态和宠物 |
| 开启减少动态效果，或暂停动画 | 保持安静的显示效果 |

工作时轮廓流动，已识别的问题等待使用介入色脉冲，错误使用红色脉冲，空闲时进入低亮状态。回合完成**不等于**存在未读结果。

<a id="privacy"></a>
## 会话数据留在本机

默认来源只读当前用户的 `~/.codex/` 数据库和活动会话事件，不修改 Codex 数据，不发送聊天、批准请求或标记已读。事件解析在内存中处理，诊断输出不包含会话标题或聊天载荷。

**默认会显示标题。** 未发布源码新增标题隐私，覆盖岛、悬停和 VoiceOver；分享屏幕前也可按需隐藏状态岛。审批按钮识别是默认关闭的可选辅助功能，需要用户自行授权；系统权限比应用实际执行的只读检查范围更广。详见 [安全与隐私](../SECURITY.md)。

<a id="compatibility"></a>
## 当前能力与边界

| 能力 | 当前范围 |
| --- | --- |
| 本机会话标题、活动、已识别的问答等待 | 在本机历史适配器覆盖范围内可用 |
| 审批按钮识别 | 实验功能；需主动授权辅助功能；真实审批卡片验收待完成 |
| 完整未读、远端 / 云端聊天、与 Codex 宠物完全同源 | 不支持 |
| 所有全屏 / Space 组合、显示器变化、长时性能 | 尚未完整验收 |

Codex 的内部数据格式可能变化。来源不兼容时会显示不可用，不会假装空闲。v0.7.3 起支持启动环境中的绝对目录 `CODEX_HOME`，无效覆盖会明确报错；事件失败会有界退避，并在保留数据库已证实活动的同时显示同步受限。已发布的 v0.7.2 读取 `~/.codex/`。详见 [本机来源边界](local-session-source.md)。

<a id="development"></a>
## 开发

运行基于夹具的测试：

```bash
./Scripts/test.sh
```

测试不需要真实聊天或个人图片。本机安装版素材检查与性能基准需显式开启，方式见 [贡献指南](../CONTRIBUTING.md) 与 [性能说明](performance.md)。

<details>
<summary>演示与诊断</summary>

构建独立应用，使用明确标记为“演示”的状态：

```bash
PREVIEW_STATE=needsInput ./Scripts/package_app.sh
open build/CodexIslandPreview.app
```

支持的演示状态：`running`、`needsInput`、`blocked`、`ready`、`idle`。

只输出聚合诊断，不打印标题或聊天正文：

```bash
./build/CodexIsland.app/Contents/MacOS/CodexIsland --diagnose
./build/CodexIsland.app/Contents/MacOS/CodexIslandProbe --watch 10
```

自备生产者的接入方式见 [显式状态文件契约](status-input.md)。这是本项目的开发接口，不是 Codex API。

</details>

<a id="documentation"></a>
## 文档

通过 [文档索引](README.md) 查看架构、状态来源、宠物动画、性能基准与发布检查。技术文档目前主要以中文编写，项目介绍提供上方四种语言；未发布源码另支持跟随系统或英语、简繁中文、日语应用界面；v0.7.3 下载包尚不包含此功能。

<a id="contributing"></a>
## 参与贡献

欢迎报告问题、修复兼容性和改进文档。提交 PR 前请阅读 [贡献指南](../CONTRIBUTING.md)，使用合成夹具并对诊断资料脱敏。各语言 README 以英文主版本为基准同步，规则见 [翻译维护说明](README.md#readme-translations)。

<a id="license"></a>
## 致谢与许可

由 **Water** 创建。水猫标识将水波与代码提示符结合；视觉方向参考了 [Atoll](https://github.com/Ebullioscopic/Atoll)。

项目代码、文档和新品牌素材采用 [MIT](../LICENSE)。Codex 名称及运行时加载的第三方宠物素材保留各自权属，详见 [素材与商标说明](../THIRD_PARTY_NOTICES.md)。
