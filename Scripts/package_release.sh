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

### Changes

- Discover local custom pets and cloud pets already cached by Codex, load their names and animation, and preserve the selection across restarts. No network requests or personal images are bundled.
- Preserve loaded pets when their source is temporarily unavailable; migrate the former system-icon selection to the built-in Codex pet.
- Retry failed session events with bounded backoff, expose limited synchronization, and add manual status resynchronization.
- Share explicit CODEX_HOME validation across the app, probe, and diagnostics.
- Refine the menu-bar and settings brand icons and add eight synthetic native state previews to all four README languages.

### Downloads

- Universal DMG and ZIP for Apple Silicon and Intel; macOS 14+ deployment target.
- SHA256SUMS.txt for download verification: `shasum -a 256 -c SHA256SUMS.txt`.
- App version {version}, build {build}; source commit `{commit}`.

### Install

Open the DMG and drag CodexIsland.app to Applications, or unzip the ZIP. Launch the app and use its menu-bar controls. Install Codex for live local status.

### Preview limitations

- Ad-hoc signed, **not Developer ID signed or notarized**. macOS may block an unidentified developer; build from source if you prefer.
- Universal binary architecture checks do not replace real-device validation on Intel or the minimum macOS version.
- A single event record over 1 MiB still causes limited synchronization. Backoff and manual resynchronization do not bypass it; database-confirmed activity remains available, but question state may be incomplete.
- Private Codex database/asset formats can change. Complete unread state, remote/cloud chats and full pet-state parity are unsupported.
- Approval-button recognition is opt-in and experimental. Fullscreen/Spaces combinations and 30-minute whole-app performance remain under validation.
- No personal pet images, private session data, or signing credentials are included.

See the repository README, security policy, changelog and compatibility documentation for details. This independent project is not affiliated with OpenAI.
''')
PY
echo "Created build/$BASE.zip, build/$BASE.dmg and build/SHA256SUMS.txt"
