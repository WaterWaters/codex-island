# 显式外部状态输入

该格式属于 Codex Island 自己的开发集成契约，**不是 Codex API，也没有现成的真实生产者**。用户需要显式指定绝对路径，应用不会自动寻找或生成此文件。

```bash
./build/CodexIsland.app/Contents/MacOS/CodexIsland --status-file /absolute/path/snapshot.json
```

外部来源模式会在界面中标注“外部状态源”。仅接受普通文件，拒绝 FIFO、设备和目录；对已打开描述符检查类型，避免命名管道阻塞。文件最多 256 KiB，每 500 ms 只读一次。生产者应在同目录写入临时文件后原子替换；应每 15 秒或更短时间刷新完整快照，即使工作状态没有变化。

```json
{
  "schemaVersion": 1,
  "source": "example-provider",
  "sessionID": "provider-process-session-id",
  "observedAt": "2026-10-21T02:00:00Z",
  "isComplete": true,
  "sessionTitle": "设计 Codex 浮窗小工具",
  "activity": "runningCommand",
  "activities": ["running", "needsInput", "running"]
}
```

示例时间只用于说明结构，使用前必须替换成当前 UTC 时间。`observedAt` 表示本次完整观测时间，不是最后一次状态变化时间。

| 字段 | 规则 |
| --- | --- |
| `schemaVersion` | 必须为 1 |
| `source` | 非空来源名称；不包含凭据或聊天内容 |
| `sessionID` | 非空生产者会话标识；重启时更新 |
| `observedAt` | ISO 8601 UTC 时间；不能落后当前时间超过 30 秒或领先超过 5 秒 |
| `isComplete` | 必须为 true；范围不完整不能按空闲处理 |
| `activities` | 每项活动一个状态，允许 running / needsInput / blocked / ready；最多 10000 项 |

只有完整快照的空数组才表示空闲。数组不能包含 `idle`。未知状态、版本错误、数据过期、文件读取或解析失败都会显示“状态暂不可用”。

同一会话时间倒退会被拒绝；新会话替换旧会话后，旧会话再次出现也会被拒绝。点击不修改文件，不改变快照状态。没有“读取聊天正文”“批准”“标记已读”“终止任务”等反向控制接口。

归约优先级为 needsInput → blocked → ready → running。Ready 的移除必须由生产者提供的真实已读状态决定，应用不设置倒计时清除。

v0.4 增加可选的 `sessionTitle` 和 `activity`，旧版文件仍可读取。标题第一行展示，合并空白并限制长度；活动第二行展示，可选 working / thinking / runningCommand / ranCommand / editingFiles / editedFiles / usingTool / usedTool / searching / responding / needsInput / failed / commandFailed / idle。缺标题时显示 Codex；空活动数组进入 idle 常驻，不再隐藏。只有明确检测到 Codex 退出，默认实时来源才隐藏；显式文件和演示来源始终可见。
