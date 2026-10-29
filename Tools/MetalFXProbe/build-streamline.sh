#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${GGGMAC_STREAMLINE_HEADERS:?Set this to the public Streamline include directory}"
compiler="${ZIG:-zig}"
export ZIG_GLOBAL_CACHE_DIR="${GGGMAC_ZIG_CACHE:-$PWD/.build/zig-cache}"
"$compiler" c++ -target x86_64-windows-gnu -std=c++17 -Os \
  -I"$GGGMAC_STREAMLINE_HEADERS" Tools/MetalFXProbe/streamline.cpp \
  -o "${GGGMAC_STREAMLINE_PROBE_OUTPUT:-/tmp/GGGMacStreamlineProbe.exe}" -ldxgi -ldxguid -municode
