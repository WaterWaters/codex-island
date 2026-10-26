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

A native macOS status island for local Codex sessions, with activity, recognized question waits, appearance settings, and optional locally loaded built-in and custom pets.

### 本次修复

- 修复发布包启动时 SwiftPM 资源定位失败引发的崩溃，四语言和品牌统一优先读取随包 Contents/Resources；开发运行仍兼容 SwiftPM 资源。
- 新增 `--check-resources`，打包时实际执行产物并检查四语言与图标；检查不创建界面、不读 Codex 数据、不写正式偏好。
- 刘海 Mini 外框改为两侧各 1.5 pt、下沿 2 pt，主跑马灯及等待 / 错误轮廓加粗到 2.4 pt；普通屏 44 × 22 pt 胶囊保持原样。
- 单块 185 × 32 pt 刘海 / 2× 屏幕完成隔离的运行、等待、错误与关闭动画检查。用户确认收窄后的贴边尺寸合适；这不代表所有刘海机型或完整生命周期均已验收。

### 升级与兼容

- 建议 0.8.0 安装包用户升级本补丁；退出旧应用后替换应用并重新打开，原有偏好保留。
- 相对 v0.8.0 未发现数据库结构 / 迁移变更，无本版本新增 DDL 步骤；没有新增、删除或升级运行 / 构建依赖。
- 继续提供 macOS 14+ 的 Apple Silicon / Intel 通用包，ad-hoc 签名，未 Developer ID 签名或公证。

### Downloads

- Universal DMG and ZIP for Apple Silicon and Intel; macOS 14+ deployment target.
- SHA256SUMS.txt for download verification: `shasum -a 256 -c SHA256SUMS.txt`.
- App version {version}, build {build}; source commit `{commit}`.

### Install

Open the DMG and drag CodexIsland.app to Applications, or unzip the ZIP. Launch the app and use its menu-bar controls. Install Codex for live local status.

### Preview limitations

- Ad-hoc signed, **not Developer ID signed or notarized**. macOS may block an unidentified developer; build from source if you prefer.
- Universal binary architecture checks do not replace real-device validation on Intel or the minimum macOS version.
- Event parsing validates large records incrementally and retains a bounded state/question projection. Malformed records or structure/semantic budget limits still cause limited synchronization; incomplete question state is not treated as complete.
- Private Codex database/asset formats can change. Complete unread state, remote/cloud chats and full pet-state parity are unsupported.
- Native gallery rasterization is a separate opt-in desktop integration check; headless Intel rendering is unverified.
- Approval-button recognition is opt-in and experimental. Physical notch/display combinations, hot-plugging, fullscreen/Spaces, login and sleep/lock still need broader real-device validation. Mini screenshots are synthetic native view renders.
- Performance measurement, budgets and optimization are deferred to a separate effort; earlier baselines do not certify the new Mini mode.
- No personal pet images, private session data, or signing credentials are included.

See the repository README, security policy, changelog and compatibility documentation for details. This independent project is not affiliated with OpenAI.
''')
PY
echo "Created build/$BASE.zip, build/$BASE.dmg and build/SHA256SUMS.txt"
