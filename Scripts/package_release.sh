#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TAG=${1:-}
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 vMAJOR.MINOR.PATCH" >&2
  exit 2
fi
python3 Scripts/verify_repository.py
ARCHES="arm64 x86_64" ./Scripts/package_app.sh release
APP="$ROOT/build/CodexIsland.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
test "$TAG" = "v$VERSION"
codesign --verify --deep --strict "$APP"
python3 - "$APP" <<'PY'
from pathlib import Path
import re
import subprocess
import sys
root = Path(sys.argv[1])
expected = {
    'Contents/MacOS/CodexIsland', 'Contents/MacOS/CodexIslandProbe',
    'Contents/Info.plist', 'Contents/Resources/AppIcon.icns',
    'Contents/_CodeSignature/CodeResources',
    'Contents/Resources/CodexIsland_CodexIsland.bundle/Contents/Info.plist',
    'Contents/Resources/CodexIsland_CodexIsland.bundle/Contents/Resources/Brand/AppIcon.png',
}
actual = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
expected.update(f'Contents/Resources/CodexIsland_CodexIsland.bundle/Contents/Resources/{language}.lproj/Localizable.strings'
                for language in ('en', 'zh-Hans', 'zh-Hant', 'ja'))
if actual != expected or any(p.is_symlink() for p in root.rglob('*')):
    raise SystemExit('Unexpected bundle contents; refusing to package private or unreviewed files.')
for name in ['CodexIsland', 'CodexIslandProbe']:
    binary = root / 'Contents/MacOS' / name
    architectures = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
    if set(architectures) != {'arm64', 'x86_64'}:
        raise SystemExit('Missing or unexpected universal binary architectures.')
    metadata = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(binary)], text=True)
    versions = re.findall(r'^\s*minos ([0-9.]+)$', metadata, re.M)
    if len(versions) != 2 or any(tuple(map(int, v.split('.')[:2])) > (14, 0) for v in versions):
        raise SystemExit('A universal binary requires a newer OS than the advertised macOS 14 target.')
print('App bundle matches the public file allowlist.')
PY
BASE="CodexIsland-$TAG-macos-universal"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/build/$BASE.zip"
STAGING=$(mktemp -d "$ROOT/build/.dmg-XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/CodexIsland.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname 'Codex Island' -srcfolder "$STAGING" -ov -format UDZO "$ROOT/build/$BASE.dmg"
(
  cd "$ROOT/build"
  shasum -a 256 "$BASE.zip" "$BASE.dmg" > SHA256SUMS.txt
)
COMMIT=$(git rev-parse --verify HEAD 2>/dev/null || true)
python3 - "$TAG" "$VERSION" "$BUILD" "${COMMIT:-uncommitted}" <<'PY'
from pathlib import Path
import sys
tag, version, build, commit = sys.argv[1:]
Path('build/RELEASE_NOTES.md').write_text(f'''## Codex Island {tag} — Preview

A native macOS status island for local Codex and Claude Code sessions, with source selection, automatic rotation, input reminders, and optional local Codex pets.

### 本次新增

- 新增只读 Claude Code 来源，校验活动注册表、进程启动时间与会话身份，显示工作中、需要你、受阻、空闲或来源不可用；不发送聊天、不执行审批、不修改来源数据。
- 菜单与连接设置可选 Codex、Claude 或自动轮播；默认仍为 Codex。通常每 6 秒轮播，优先保留介入 / 受阻来源，悬停暂停；状态、悬停和 VoiceOver 标明来源。
- 点击打开当前来源桌面应用，不猜测终端或精确会话。双来源连接健康与脱敏诊断独立展示；探针支持 `--source codex|claude|all`。
- 修复 Swift 6.0 对探针异构 JSON 返回值的隔离检查，异步边界仅传递不可变 JSON 字节，保持诊断字段和退出码。
- Claude 支持启动环境中的绝对目录 `CLAUDE_CONFIG_DIR`；坏事件有界退避，来源失败不假装空闲。四语言 README、来源、使用、架构与隐私文档同步。

### 升级与兼容

- 退出旧应用后替换并重开；已有偏好保留，缺失或未知来源字段回落 Codex。宠物仍使用本机 Codex 素材。
- 相对 v0.8.1 未发现数据库结构 / 迁移变更，无本版本新增 DDL 步骤。新增内部 ClaudeFeed 模块，无第三方依赖新增、移除或升级；源码仍使用 `./Scripts/package_app.sh` 构建。
- Claude 已记录兼容对象为 Code 2.1.309 的 claude-desktop-3p 入口。CLI / IDE 注册表覆盖仍待验证，私有格式可能变化；缺失 / 歧义数据保守降级，不保证全局状态或完整未读。
- macOS 14+ Apple Silicon / Intel 通用包，ad-hoc 签名，未 Developer ID 签名或公证。

### Downloads

- Universal DMG and ZIP for Apple Silicon and Intel; macOS 14+ deployment target.
- SHA256SUMS.txt for download verification: `shasum -a 256 -c SHA256SUMS.txt`.
- App version {version}, build {build}; source commit `{commit}`.

### Install

Open the DMG and drag CodexIsland.app to Applications, or unzip the ZIP. Launch the app and use its menu-bar controls. Install Codex or a supported Claude Code entry point for live local status; select the provider in Settings → Connection.

### Preview limitations

- Ad-hoc signed, **not Developer ID signed or notarized**. macOS may block an unidentified developer; build from source if you prefer.
- Universal binary architecture checks do not replace real-device validation on Intel or the minimum macOS version.
- Event parsing validates large records incrementally and retains a bounded state/question projection. Malformed records or structure/semantic budget limits still cause limited synchronization; incomplete question state is not treated as complete.
- Private Codex and Claude data formats can change. Complete unread state, remote/cloud chats and full pet-state parity are unsupported.
- Native gallery rasterization is a separate opt-in desktop integration check; headless Intel rendering is unverified.
- Approval-button recognition is opt-in and experimental. Physical notch/display combinations, hot-plugging, fullscreen/Spaces, login and sleep/lock still need broader real-device validation. Mini screenshots are synthetic native view renders.
- Performance measurement, budgets and optimization are deferred to a separate effort; earlier baselines do not certify the new Mini mode.
- No personal pet images, private session data, or signing credentials are included.

See the repository README, security policy, changelog and compatibility documentation for details. This independent project is not affiliated with OpenAI or Anthropic.
''')
PY
echo "Created build/$BASE.zip, build/$BASE.dmg and build/SHA256SUMS.txt"
