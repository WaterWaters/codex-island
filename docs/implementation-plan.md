# 实施进度与验收待办

## 0.7.2 发布准备

- [x] 源码安全、稳定性和性能审查；区分可利用漏洞与本机健壮性问题。
- [x] 修复时长乘法溢出、外部文件阻塞及长回合问答状态累积。
- [x] 合并刷新、图片解码前检查尺寸，补充有效反例测试及显式合成基准。
- [x] 公开构建移除个人宠物和相关预览 / 元数据依赖，私有原件本机保留。
- [x] 增加 MIT、忽略规则、安全 / 隐私 / 贡献 / 素材说明、GitHub CI 和报告模板。
- [x] 新版公开文件集的最终测试及打包验证，结果登记在 release-readiness.md。
- [x] 建立独立 GitHub 仓库、启用私密漏洞报告，推送公开源码。
- [x] 配置 macOS 14 Apple Silicon / macOS 15 Intel CI，以及版本标签触发的通用 DMG / ZIP Preview 发布流程。
- [x] 首次远端 macOS 14 Apple Silicon / macOS 15 Intel 测试、打包及签名检查通过，创建 `v0.7.2` 标签。

对应提交的实际运行结果见 [Actions](https://github.com/WaterWaters/codex-island/actions)，发布结果见 [Releases](https://github.com/WaterWaters/codex-island/releases)。

## 后续真实场景

- [ ] 辅助功能权限下真实允许 / 拒绝审批卡片与关闭恢复。
- [ ] 全屏、跨 Space、显示器热插拔、睡眠 / 锁屏恢复与 Codex 重启。
- [ ] macOS 14 和 Intel 实机验证；当前构建目标不等于运行验证。
- [ ] 完成未读与远端 / 云端状态来源。
- [ ] 30 分钟整应用 CPU / 内存 / 能耗采样。
- [ ] 损坏事件退避 / 恢复策略、解析器 fuzzing 和更严格的本机文件竞态加固。

当前交付为可自行构建的本机会话兼容工具。源码准备、实际上传、正式二进制分发分别记录，不将本机 ad-hoc 签名当作公证或远端发布成功。
