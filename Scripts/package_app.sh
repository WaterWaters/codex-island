#!/usr/bin/env bash
# Adapted from the macos-spm-app-packaging skill's package_app.sh template.
set -euo pipefail

CONF=${1:-release}
case "$CONF" in debug|release) ;; *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;; esac
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
APP_NAME=CodexIsland
BINARY_NAME=CodexIsland
BUNDLE_ID=dev.water.codex-island
PREVIEW_STATE=${PREVIEW_STATE:-}
if [[ -n "$PREVIEW_STATE" ]]; then
  case "$PREVIEW_STATE" in running|needsInput|blocked|ready|idle) ;;
    *) echo "Invalid PREVIEW_STATE" >&2; exit 2 ;;
  esac
  APP_NAME=CodexIslandPreview
  BUNDLE_ID=dev.water.codex-island.preview
fi
MACOS_MIN_VERSION=14.0
MARKETING_VERSION=0.8.1
BUILD_NUMBER=15
ARCH_LIST=( ${ARCHES:-$(uname -m)} )
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"

BINARIES=()
PROBE_BINARIES=()
for ARCH in "${ARCH_LIST[@]}"; do
  case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 2 ;; esac
  swift build -c "$CONF" --arch "$ARCH" --disable-sandbox \
    --cache-path "$ROOT/.build/cache" --config-path "$ROOT/.build/config" \
    --security-path "$ROOT/.build/security"
  BIN_DIR=$(swift build --show-bin-path -c "$CONF" --arch "$ARCH" --disable-sandbox \
    --cache-path "$ROOT/.build/cache" --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security")
  mkdir -p "$ROOT/.build/package-binaries/$ARCH"
  cp "$BIN_DIR/$BINARY_NAME" "$ROOT/.build/package-binaries/$ARCH/$BINARY_NAME"
  cp "$BIN_DIR/CodexIslandProbe" "$ROOT/.build/package-binaries/$ARCH/CodexIslandProbe"
  BINARIES+=("$ROOT/.build/package-binaries/$ARCH/$BINARY_NAME")
  PROBE_BINARIES+=("$ROOT/.build/package-binaries/$ARCH/CodexIslandProbe")
done

APP="$ROOT/build/${APP_NAME}.app"
mkdir -p "$ROOT/build"
STAGING=$(mktemp -d "$ROOT/build/.package-XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
STAGED_APP="$STAGING/${APP_NAME}.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$ROOT/Artwork/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
# Reconstruct the resource bundle from an explicit public file list. Never
# copy a build bundle wholesale: incremental outputs can retain old resources.
BRAND_BUNDLE="$STAGED_APP/Contents/Resources/CodexIsland_CodexIsland.bundle"
mkdir -p "$BRAND_BUNDLE/Contents/Resources/Brand"
cp "$ROOT/Sources/CodexIsland/Resources/Brand/AppIcon.png" "$BRAND_BUNDLE/Contents/Resources/Brand/AppIcon.png"
for LANGUAGE in en zh-Hans zh-Hant ja; do
  mkdir -p "$BRAND_BUNDLE/Contents/Resources/$LANGUAGE.lproj"
  cp "$ROOT/Sources/CodexIsland/Resources/Localization/$LANGUAGE.lproj/Localizable.strings" \
    "$BRAND_BUNDLE/Contents/Resources/$LANGUAGE.lproj/Localizable.strings"
done
cat > "$BRAND_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.water.codex-island.brand</string>
  <key>CFBundleName</key><string>CodexIsland_CodexIsland</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
</dict></plist>
PLIST

if [[ ${#BINARIES[@]} -gt 1 ]]; then
  lipo -create "${BINARIES[@]}" -output "$STAGED_APP/Contents/MacOS/$APP_NAME"
  lipo -create "${PROBE_BINARIES[@]}" -output "$STAGED_APP/Contents/MacOS/CodexIslandProbe"
else
  cp "${BINARIES[0]}" "$STAGED_APP/Contents/MacOS/$APP_NAME"
  cp "${PROBE_BINARIES[0]}" "$STAGED_APP/Contents/MacOS/CodexIslandProbe"
fi
chmod +x "$STAGED_APP/Contents/MacOS/$APP_NAME"
cat > "$STAGED_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>CodexIsland</string>
  <key>CFBundleDisplayName</key><string>Codex Island</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CodexIslandPreviewState</key><string>${PREVIEW_STATE}</string>
</dict></plist>
PLIST
xattr -cr "$STAGED_APP"
codesign --force --sign - "$STAGED_APP/Contents/MacOS/CodexIslandProbe"
codesign --force --sign - "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
# Execute the packaged binary before publication. Building and signing alone
# do not prove that SwiftPM's generated resource accessor can find this layout.
"$STAGED_APP/Contents/MacOS/$APP_NAME" --check-resources
# Only replace this script's fixed build output after a successful signed build.
rm -rf "$APP"
mv "$STAGED_APP" "$APP"
echo "Created $APP"
