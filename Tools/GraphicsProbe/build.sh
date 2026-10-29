#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
compiler="${ZIG:-zig}"
export ZIG_GLOBAL_CACHE_DIR="${GGGMAC_ZIG_CACHE:-$PWD/.build/zig-cache}"
mkdir -p Sources/GGGMacCore/Resources
"$compiler" cc -target x86_64-windows-gnu -Os -s -fno-ident \
  Tools/GraphicsProbe/probe.c -o Sources/GGGMacCore/Resources/GGGMacGraphicsProbe.exe \
  -ld3d11 -ldxgi -ldxguid -lopengl32 -lgdi32 -luser32
