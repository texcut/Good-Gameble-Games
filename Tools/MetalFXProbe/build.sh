#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
compiler="${ZIG:-zig}"
export ZIG_GLOBAL_CACHE_DIR="${GGGMAC_ZIG_CACHE:-$PWD/.build/zig-cache}"
"$compiler" cc -target x86_64-windows-gnu -Os -s -fno-ident \
  Tools/MetalFXProbe/probe.c -o "${GGGMAC_METALFX_PROBE_OUTPUT:-/tmp/GGGMacMetalFXProbe.exe}"
