#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

action="${1:-build}"
if [[ "$action" != "build" && "$action" != "test" ]]; then
    echo "Usage: bash scripts/swift-tool.sh [build|test] [SwiftPM options]" >&2
    exit 1
fi
if [[ $# -gt 0 ]]; then shift; fi
build_dir="${GGGMAC_BUILD_DIR:-$PWD/.build}"
export CLANG_MODULE_CACHE_PATH="$build_dir/clang-cache"
export SWIFT_MODULECACHE_PATH="$build_dir/swift-cache"

# The standalone Swift 6.4 CLT's swiftbuild engine omits this plugin from
# its discovery paths. Explicit loading is harmless on complete toolchains.
testing_plugin="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
swift_args=("$action" --disable-sandbox --scratch-path "$build_dir"
    --cache-path "$build_dir/cache" --config-path "$build_dir/config" --security-path "$build_dir/security")
if [[ -f "$testing_plugin" ]]; then
    swift_args+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
swift "${swift_args[@]}" "$@"
