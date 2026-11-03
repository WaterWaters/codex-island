# Provider 图标来源与使用边界

`claude.svg` 与 `openai.svg` 仅用于岛内当前来源的身份识别展示：

- 图形与名称权利归 Anthropic P. C. 与 OpenAI 各自所有；本项目未取得再分发授权、不主张对其的任何权利。不构成 OpenAI / Anthropic 的官方产品、认可或合作（与 README 的独立性声明一致）。
- `claude.svg`：星芒轨迹取自 simple-icons 16.36.0（该仓库以 CC0 提供图标集，商标权利仍归 Anthropic），填充改为官方 Crail 色 `#D97757`。
- `openai.svg`：花结轨迹取自 `@lobehub/icons` 6.14.0 的 OpenAI Mono 组件（单一 path、无底板），填充采用 ChatGPT 产品色 `#74AA9C`。2026-11-03 用户指示：本地 `codex` 入口也用 OpenAI/ChatGPT 标——原 codex 渐变云标（提取自 `@lobehub` Codex Color 组件的 `#B1A7FF→#7A9DFF→#3941FF` 渐变云形，曾按 24pt bbox 202..816 裁剪与中性暗掩膜）退役，历史版本保留在本机 `local/provider-logos/`（git 忽略）。
- 运行时删除/移除这些文件不影响岛工作：缺 SVG 时回落本机已装 App 的无框资源，再回落 app icon。
