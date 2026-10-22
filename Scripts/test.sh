#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"
SWIFT_TOOLCHAIN_BIN=$(dirname "$(xcrun --find swiftc)")
TESTING_PLUGIN="$SWIFT_TOOLCHAIN_BIN/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
PLUGIN_ARGS=()
# Swift 6.4 CLT's SwiftBuild does not discover the bundled Testing macro plugin.
if [[ -f "$TESTING_PLUGIN" ]]; then
  PLUGIN_ARGS=(-Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN")
fi
exec swift test --disable-sandbox --cache-path "$ROOT/.build/cache" \
  --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security" \
  "${PLUGIN_ARGS[@]}" "$@"
