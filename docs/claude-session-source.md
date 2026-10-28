# 本机 Claude Code 会话来源 v1

这是受限兼容来源，不是 Anthropic 官方稳定 API，也不与 Codex 来源等价。验证对象为 Claude Code `2.1.309`（`entrypoint=claude-desktop-3p`），macOS 27.0.1；最低部署目标仍未变为 macOS 14 实测。

## 数据目录配置

GUI、原生探针和 `--diagnose` 共用 `ClaudeFeedConfiguration`。没有 `CLAUDE_CONFIG_DIR` 时读取当前用户 `~/.claude`；显式设置必须是非空、无 NUL 的绝对目录。空值、相对路径、`~` 和 `file://` 字符串均报 `invalidConfiguration`，不静默回退。目录不存在时报 `missingLocalData`，不创建目录。

```bash
CLAUDE_CONFIG_DIR=/absolute/claude-home ./build/CodexIsland.app/Contents/MacOS/CodexIsland
CLAUDE_CONFIG_DIR=/absolute/claude-home ./build/CodexIsland.app/Contents/MacOS/CodexIslandProbe --source claude
```

## 读取内容与范围

- `~/.claude/sessions/<pid>.json`：活动会话注册表。只读取 `pid`、`sessionId`、`cwd`、`startedAt`、`status`、`statusUpdatedAt`、`updatedAt`、`name`、`entrypoint` 和 `version`。
- `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`：会话事件流。目录名推导失败时在 `projects` 下做有界扫描，同一会话出现多个候选时报未确认，不猜测。
- `<sessionId>/custom-title.json`：会话自定义标题，最多 512 UTF-8 字节。

只读、不写 `~/.claude`，不发送消息、不批准权限、不标记已读。JSONL 字节会经过解析器；保留投影不包含提示词正文、思考内容、工具参数或工具输出：事件投影只保留 `type`、`subtype`、`timestamp`、`isSidechain`、`sessionId`、`message.stop_reason`、工具调用的 `id` / `name`、工具结果的 `tool_use_id`、`isApiErrorMessage`、`customTitle` 与 `agentName`。

预算：注册表每次最多 64 个文件、每文件 64 KiB；事件流首次读取尾部 2 MiB，之后每次每会话最多 256 KiB、单行 4 MiB、最多 32 个活动会话；标题文件 8 KiB。

## 进程存活与身份

`~/.claude/sessions/<pid>.json` 可能因崩溃或强杀残留。适配器用 `proc_pidinfo(PROC_PIDTBSDINFO)` 读取进程启动时间，与注册表 `startedAt` 相差不超过 2 秒才视为同一会话；pid 复用因此被拒绝。注册表里的 `procStart` 是本地化文本，不参与判断。文件系统身份使用 `(device, inode, size, mtime)`；文件替换或截断后重建游标。

## 状态映射

| 证据 | 浮窗行为 | 边界 |
| --- | --- | --- |
| 注册表 `status=waiting`（`waitingFor` 为 `input needed` / `worker request` / `sandbox request` / `dialog open` 等） | 需要你 | 注册表值决定，事件流在此刻通常没有新记录 |
| 当前回合存在未配对的 `AskUserQuestion` 或 `ExitPlanMode` 调用 | 需要你 | 其他工具挂起不等于等待用户 |
| 注册表 `status=busy`，或回合内仍有未配对工具调用，或最后一条根记录是用户提示 / 工具结果 | 工作中 | 长时间无事件不等于结束 |
| 最近回合级证据是 `isApiErrorMessage` 或 `system/api_error` | 工作受阻 | 单次工具失败、`permission-rule` 自动拒绝、`user-rejected` 不进入受阻 |
| 最近的终止型 `stop_reason`（`end_turn` / `stop_sequence` 等）且注册表 `status=idle` | 空闲，保留标题 | 完成不等于未读 |
| 注册表状态未知、事件流不可读、身份校验失败、尾部窗口找不到回合起点 | 状态暂不可用 / 同步受限 | 不显示空闲，不推断等待 |
| 没有存活会话 | Claude 未运行 | 不把“没有会话”当空闲 |

`isSidechain=true` 的记录属于子代理，不参与根会话状态。`compact_boundary`、`stop_hook_summary` 等记录不结束回合。

多个活动会话按 `needsInput → blocked → running → idle` 选择；同优先级按最近活动时间，再按会话标识排序。

## 失败与恢复

坏 JSON、非法 UTF-8、会话标识不符进入按会话退避：1、2、4、8、16、30 秒，使用单调时间；退避期间保留注册表可证实的“工作中”，并报告“同步受限”。成功追平后清除退避。文件修复、替换或截断在下一次读取时检查。

## 已知边界

- 注册表只有 `idle` / `busy` / `waiting` 三个已观测值；等待原因来自 `waitingFor`，未列出的原因同样按需要你处理，但不在诊断中输出原文。
- 权限弹窗由注册表 `status=waiting` 反映，不读取窗口、不使用辅助功能权限。
- CLI / IDE 入口是否都写注册表尚未完整验证；缺失时明确报不支持，不伪造空闲。
- 事件流只依赖尾部窗口；更早历史不参与当前回合判断。
- 不猜测终端窗口。
